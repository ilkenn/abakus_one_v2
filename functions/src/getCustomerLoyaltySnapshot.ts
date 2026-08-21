import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { SINGLE_TENANT_ORGANIZATION_ID, TENANT_CUSTOMERS_COLLECTION } from "./completeCustomerProfile";
import { LOYALTY_ACCOUNTS_COLLECTION } from "./loyaltyLedger";

/**
 * `getCustomerLoyaltySnapshot` — Boncuk Loyalty Program P1 (2026-08-20).
 *
 * The one minimal, trusted account-provisioning/read path for the loyalty
 * ledger foundation. Mirrors `getCustomerProfileCompletionState.ts`'s own
 * shape (narrow read-only response, no client-trusted identity/tenant
 * input) plus `completeCustomerProfile.ts`'s transactional idempotent-
 * create discipline for the one write this callable can perform.
 *
 * **Correction A (locked instruction) — `organizationId` is never
 * client-supplied.** This callable's `request.data` is never even read —
 * there is no field a client could set to request another tenant's
 * account. Organization is resolved exclusively via
 * [SINGLE_TENANT_ORGANIZATION_ID] (imported from `completeCustomerProfile.ts`,
 * not re-declared), the same hand-mirrored-with-`kSingleTenantOrganizationId`
 * single-tenant constant every other customer-facing callable already
 * resolves canonical org from. When real multi-tenant customer membership
 * exists, this is the one line that changes — to resolve the caller's
 * actual `tenantCustomers` membership(s) instead of this constant — not a
 * wider architectural change; every other piece of this callable (uid from
 * `request.auth`, membership verified server-side, account keyed by
 * `{organizationId}_{uid}`) is already multi-tenant-shaped.
 *
 * **Never trusts client-supplied identity data** — the same
 * `completeCustomerProfile.ts`/`getCustomerProfileCompletionState.ts`
 * discipline: `uid` is always `request.auth.uid`; the caller must be a
 * real, phone-verified customer (`request.auth.token.firebase
 * .sign_in_provider === "phone"`) — an anonymous/guest technical identity
 * (e.g. table/takeaway QR sessions) is rejected before anything else runs.
 *
 * **Tenant membership is independently re-verified server-side**, via the
 * Admin SDK (which bypasses `firestore.rules` entirely) — `tenantCustomers`'
 * own rule is staff-only (`isOrgMember`), so an ordinary customer could
 * never perform this read themselves even if they tried; this callable
 * reads it as the trusted party, exactly as `getCustomerProfileCompletionState
 * .ts` already does for the identical collection. No shared helper exists
 * in this codebase for this specific check (confirmed before writing this
 * file) — the inline shape mirrors `requestCustomerPhotoUploadGrant.ts`'s
 * own membership check exactly.
 *
 * **Idempotent, never resets existing state.** A plain (non-transactional)
 * read handles the overwhelming common case — an already-provisioned
 * account — as a pure read with zero writes, zero `revision` bump, zero
 * `updatedAt` touch. Only a genuinely first-time caller falls through to a
 * transaction, which re-reads before writing (mirrors `completeCustomerProfile
 * .ts`'s "reads first, always" transaction discipline) so a concurrent
 * first call for the same uid can never create two documents or double-
 * initialize — the loser of the race simply returns the winner's data,
 * untouched.
 *
 * **Does not fabricate a ledger entry.** A brand-new zero account is
 * created with zero `loyaltyLedgerEntries` documents — per the locked
 * instruction, provisioning itself is not a loyalty *event*.
 *
 * **Returns only the customer's own narrow snapshot** — never
 * `organizationId`/`customerId`/`revision`/timestamps, none of which any
 * client needs yet (no Flutter UI consumes this callable this phase).
 */

export interface LoyaltyAccountData {
  organizationId: string;
  customerId: string;
  spendableBalance: number;
  earningRemainderMinorUnits: number;
  lifetimeEarned: number;
  lifetimeRedeemed: number;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  revision: number;
}

interface GetCustomerLoyaltySnapshotResult {
  spendableBalance: number;
  earningRemainderMinorUnits: number;
  lifetimeEarned: number;
  lifetimeRedeemed: number;
}

export const getCustomerLoyaltySnapshot = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request): Promise<GetCustomerLoyaltySnapshotResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "Loyalty requires a real, phone-verified customer identity.",
      );
    }
    const uid = request.auth.uid;

    // Correction A — never client-supplied; request.data is never read.
    const organizationId = SINGLE_TENANT_ORGANIZATION_ID;

    const db = getFirestore();

    const membershipSnap = await db
      .collection(TENANT_CUSTOMERS_COLLECTION)
      .doc(`${organizationId}_${uid}`)
      .get();
    if (!membershipSnap.exists) {
      throw new HttpsError("permission-denied", "You are not a customer of this organization.");
    }

    const accountRef = db.collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`);

    const existingSnap = await accountRef.get();
    const account: LoyaltyAccountData = existingSnap.exists
      ? (existingSnap.data() as LoyaltyAccountData)
      : await db.runTransaction(async (tx): Promise<LoyaltyAccountData> => {
          // Reads first, always — mirrors completeCustomerProfile.ts's
          // established transaction discipline.
          const snap = await tx.get(accountRef);
          if (snap.exists) {
            // Lost the race to a concurrent first call — return the
            // winner's data untouched, never re-initialize.
            return snap.data() as LoyaltyAccountData;
          }
          const now = Timestamp.now();
          const initial: LoyaltyAccountData = {
            organizationId,
            customerId: uid,
            spendableBalance: 0,
            earningRemainderMinorUnits: 0,
            lifetimeEarned: 0,
            lifetimeRedeemed: 0,
            createdAt: now,
            updatedAt: now,
            revision: 1,
          };
          tx.set(accountRef, initial);
          return initial;
        });

    return {
      spendableBalance: account.spendableBalance,
      earningRemainderMinorUnits: account.earningRemainderMinorUnits,
      lifetimeEarned: account.lifetimeEarned,
      lifetimeRedeemed: account.lifetimeRedeemed,
    };
  },
);

export type { GetCustomerLoyaltySnapshotResult };
