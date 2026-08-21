import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { SINGLE_TENANT_ORGANIZATION_ID, TENANT_CUSTOMERS_COLLECTION } from "./completeCustomerProfile";
import { LOYALTY_ACCOUNTS_COLLECTION } from "./loyaltyLedger";
import {
  resolveActiveLoyaltyPolicy,
  sanitizeLoyaltyPolicyForCustomer,
  projectCarryToPolicyProgress,
  parseCarryComponent,
  formatCarryComponent,
  ZERO_BONCUK_CARRY,
  type SanitizedLoyaltyPolicy,
  type BoncukFraction,
} from "./loyaltyPolicy";

/**
 * `getCustomerLoyaltySnapshot` — Boncuk Loyalty Program P1 (2026-08-20),
 * extended P2B-B (2026-08-22).
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
 * **P2B-B (2026-08-22) — `boncukDebt` added.** A new zero account now
 * provisions it at `0`. The RESPONSE gains `boncukDebt` (architectural
 * preference: a customer-facing UX will eventually need to explain why
 * new earning is temporarily paying down debt rather than becoming
 * spendable) but deliberately NOT the raw `earningCarryNumerator`/
 * `earningCarryDenominator` — those are internal accounting provenance
 * (an exact fraction, not something any current or foreseeable UI needs
 * to render directly), always projected into `earningRemainderMinorUnits`/
 * `minorUnitsUntilNextBoncuk` before leaving this callable.
 *
 * **Legacy-account read tolerance, distinct from the earning transaction's
 * strict fail-closed behavior.** This callable performs no financial
 * computation and no write for an existing account — a pure read. If an
 * existing (pre-P2B) account document is missing `boncukDebt`
 * (`undefined`), the response substitutes `0` for display purposes only;
 * the stored document itself is never backfilled here. This is
 * deliberately more lenient than `loyaltyOrderEarning.ts`'s own legacy-
 * account handling, which performs real financial math and therefore
 * fails closed on an inconsistent legacy account rather than guessing —
 * see that file's own doc comment for why a lenient default is safe here
 * specifically (nothing is computed or persisted from this value).
 *
 * **Returns only the customer's own narrow snapshot** — never
 * `organizationId`/`customerId`/`revision`/timestamps/the raw
 * `earningCarryNumerator`/`earningCarryDenominator` fraction.
 *
 * **Configurable Loyalty Economics (2026-08-24) — the response now also
 * carries the organization's sanitized current policy.** Boncuk economics
 * are no longer a Flutter-side compile-time constant; the customer app
 * renders "X TL → Y Boncuk"/"1 Boncuk → Z TL"/the earning-progress
 * denominator from these real, server-resolved fields. Resolved via
 * `loyaltyPolicy.ts`'s `resolveActiveLoyaltyPolicy` for the same
 * server-derived `organizationId` this callable already uses for the
 * account — never a second, independently-trusted organization id, and
 * never anything client-supplied. A corrupt policy document, or one that
 * was previously bootstrapped but is now unexpectedly missing (see
 * `loyaltyPolicy.ts`'s own missing-vs-first-time-provisioning boundary),
 * fails the whole call closed (`HttpsError("failed-precondition", ...)`)
 * rather than silently falling back to a fabricated rate.
 *
 * **Fractional Entitlement Carry correction (this pass) — exact,
 * policy-independent progress, never read verbatim off storage.**
 * `earningRemainderMinorUnits`/`minorUnitsUntilNextBoncuk` are computed
 * fresh at read time via `loyaltyPolicy.ts`'s `projectCarryToPolicyProgress`
 * — a customer-safe minor-unit PROJECTION of the account's real, exact
 * `earningCarryNumerator`/`earningCarryDenominator` fraction (never a
 * currency remainder in storage at all) against whatever policy is
 * CURRENTLY active. The stored carry itself is never mutated by this
 * read, and — unlike the rejected per-policy-version "earning epoch"
 * design this correction replaces — is never discounted, reset, or
 * treated as stale merely because the organization's policy has changed
 * since it last grew: a policy change can never destroy or reinterpret
 * already-earned fractional progress, it only ever supplies the rate for
 * whatever spend happens next. See `loyaltyOrderEarning.ts`'s own doc
 * comment for the full model.
 */

export interface LoyaltyAccountData {
  organizationId: string;
  customerId: string;
  spendableBalance: number;
  boncukDebt: number;
  /**
   * The currently valid WHOLE Boncuk entitlement generated by non-reversed
   * eligible order spend — an O(1) account projection, NOT `lifetimeEarned`
   * (monotonic, never decremented by a reversal), NOT `spendableBalance`
   * (net of debt-first repayment), NOT `boncukDebt`. Combined with the
   * exact fractional `earningCarry`, `validOrderEntitlementBoncuk +
   * earningCarry` is the customer's total exact order-earning entitlement
   * at this instant — the sole input, alongside one immutable historical
   * ledger entry, a full reversal needs. See `loyaltyReversalMath.ts`'s
   * own doc comment for the O(1) reversal formula and its proof.
   */
  validOrderEntitlementBoncuk: number;
  /** Canonical non-negative-integer decimal strings — an exact fraction of one Boncuk, never a currency amount and never a `Number` (see `loyaltyPolicy.ts`'s own doc comment for why). */
  earningCarryNumerator: string;
  earningCarryDenominator: string;
  lifetimeEarned: number;
  lifetimeRedeemed: number;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  revision: number;
}

interface GetCustomerLoyaltySnapshotResult {
  spendableBalance: number;
  boncukDebt: number;
  earningRemainderMinorUnits: number;
  minorUnitsUntilNextBoncuk: number;
  lifetimeEarned: number;
  lifetimeRedeemed: number;
  policy: SanitizedLoyaltyPolicy;
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
            boncukDebt: 0,
            validOrderEntitlementBoncuk: 0,
            earningCarryNumerator: formatCarryComponent(ZERO_BONCUK_CARRY.numerator),
            earningCarryDenominator: formatCarryComponent(ZERO_BONCUK_CARRY.denominator),
            lifetimeEarned: 0,
            lifetimeRedeemed: 0,
            createdAt: now,
            updatedAt: now,
            revision: 1,
          };
          tx.set(accountRef, initial);
          return initial;
        });

    const policyResult = await resolveActiveLoyaltyPolicy(db, organizationId);
    if (policyResult.status === "corrupt-policy-state" || policyResult.status === "missing-live-policy") {
      throw new HttpsError(
        "failed-precondition",
        "Loyalty economics are temporarily unavailable for this organization.",
      );
    }
    const policy = policyResult.policy;

    // Fractional Entitlement Carry — see this file's own doc comment. The
    // stored carry is ALWAYS trusted and ALWAYS combines fully into the
    // projection below, regardless of how many times the organization's
    // policy has changed since it last grew — legacy-account read
    // tolerance (see this file's own doc comment) substitutes the
    // canonical zero carry ONLY when the fields are genuinely absent
    // (a pre-this-correction document), never as a policy-driven discount.
    const carry: BoncukFraction = {
      numerator:
        typeof account.earningCarryNumerator === "string"
          ? parseCarryComponent(account.earningCarryNumerator, "loyaltyAccounts.earningCarryNumerator")
          : ZERO_BONCUK_CARRY.numerator,
      denominator:
        typeof account.earningCarryDenominator === "string"
          ? parseCarryComponent(account.earningCarryDenominator, "loyaltyAccounts.earningCarryDenominator")
          : ZERO_BONCUK_CARRY.denominator,
    };
    const progress = projectCarryToPolicyProgress(carry, policy);

    return {
      spendableBalance: account.spendableBalance,
      // Legacy-account read tolerance (see this file's own doc comment) —
      // never thrown here, never persisted, display-only default.
      boncukDebt: account.boncukDebt ?? 0,
      earningRemainderMinorUnits: progress.remainderMinorUnits,
      minorUnitsUntilNextBoncuk: progress.minorUnitsUntilNextBoncuk,
      lifetimeEarned: account.lifetimeEarned,
      lifetimeRedeemed: account.lifetimeRedeemed,
      policy: sanitizeLoyaltyPolicyForCustomer(policy),
    };
  },
);

export type { GetCustomerLoyaltySnapshotResult };
