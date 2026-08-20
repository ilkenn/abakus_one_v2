import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import {
  SINGLE_TENANT_ORGANIZATION_ID,
  CUSTOMERS_COLLECTION,
  TENANT_CUSTOMERS_COLLECTION,
  isProfileComplete,
} from "./completeCustomerProfile";

/**
 * `getCustomerProfileCompletionState` — Customer Registration CR.1 security
 * fix (2026-08-19).
 *
 * Closes a real bug a physical-device run surfaced: the Flutter client's
 * profile-completion gate previously read `tenantCustomers/{organizationId}
 * _{uid}` **directly from Firestore** to decide whether a customer needs
 * "Profilini Tamamla". That collection's own `firestore.rules` rule
 * (`allow read: if isOrgMember(resource.data.organizationId)`) only ever
 * grants read access to a **staff** member holding an `organizationAccess`
 * custom claim — ordinary phone-verified customers never carry that claim
 * (see that rule's own doc comment) and can *never* read this collection,
 * for themselves or anyone else. Every real customer's own membership check
 * was therefore structurally guaranteed to fail with `permission-denied`,
 * which the client could not distinguish from "the document genuinely
 * doesn't exist yet" — collapsing a security/backend failure into the same
 * outcome as a legitimate first-time customer, the exact ambiguity this
 * callable exists to remove.
 *
 * **The fix is server-authoritative, not a rules relaxation.** This
 * callable reads both `customers/{uid}` and `tenantCustomers/{organizationId}
 * _{uid}` via the Admin SDK (which bypasses Security Rules entirely,
 * exactly like `completeCustomerProfile` already does for its own writes)
 * and returns a narrow, safe classification — never the documents'
 * contents. `tenantCustomers`' existing rule is **unchanged**: still
 * staff-only, still denies every customer read, still denies every client
 * write. The Flutter client no longer attempts to read either document
 * directly for this purpose at all (see `customer_registration_providers
 * .dart`) — the ambiguity this callable closes is closed by removing the
 * client-side read that could never have worked, not by granting it.
 *
 * **Never trusts client-supplied identity/authorization data** — the same
 * discipline `completeCustomerProfile.ts` already established: `uid` is
 * always `request.auth.uid`, `organizationId` is never accepted from
 * `request.data` (see [SINGLE_TENANT_ORGANIZATION_ID]'s own doc comment for
 * the temporary single-tenant resolution this mirrors exactly).
 *
 * **Read-only, no transaction.** Unlike `completeCustomerProfile`, this
 * callable performs no writes, so Firestore's own transactional
 * consistency guarantees are not needed — a momentary inconsistency window
 * between the two independent reads (e.g. a concurrent `completeCustomerProfile`
 * call committing between them) is harmless: this callable only ever
 * informs client-side UI routing, it is never itself a security boundary
 * (every callable that actually needs real tenant-membership proof, e.g.
 * `requestCustomerPhotoUploadGrant`, independently re-verifies it, exactly
 * as documented there).
 *
 * **Reuses [isProfileComplete] directly** — the one, shared completeness
 * definition `completeCustomerProfile.ts` already established, never a
 * second, drifting copy.
 */

type CompletionReason = "customerMissing" | "profileFieldsIncomplete" | "membershipMissing";

interface GetCustomerProfileCompletionStateResult {
  state: "complete" | "incomplete";
  reason?: CompletionReason;
}

export const getCustomerProfileCompletionState = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request): Promise<GetCustomerProfileCompletionStateResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "Profile completion state requires a real, phone-verified customer identity.",
      );
    }
    const uid = request.auth.uid;

    // Never client-supplied — see this file's own doc comment.
    const organizationId = SINGLE_TENANT_ORGANIZATION_ID;

    const db = getFirestore();
    const [customerSnap, membershipSnap] = await Promise.all([
      db.collection(CUSTOMERS_COLLECTION).doc(uid).get(),
      db.collection(TENANT_CUSTOMERS_COLLECTION).doc(`${organizationId}_${uid}`).get(),
    ]);

    if (!isProfileComplete(customerSnap.data())) {
      return {
        state: "incomplete",
        reason: customerSnap.exists ? "profileFieldsIncomplete" : "customerMissing",
      };
    }
    if (!membershipSnap.exists) {
      return { state: "incomplete", reason: "membershipMissing" };
    }
    return { state: "complete" };
  },
);

export type { GetCustomerProfileCompletionStateResult, CompletionReason };
