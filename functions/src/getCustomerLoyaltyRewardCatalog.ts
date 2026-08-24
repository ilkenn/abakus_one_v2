import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { SINGLE_TENANT_ORGANIZATION_ID, TENANT_CUSTOMERS_COLLECTION } from "./completeCustomerProfile";
import {
  LOYALTY_REWARD_CATALOG_COLLECTION,
  parseLoyaltyRewardCatalogEntry,
  isRewardCurrentlyValid,
  sanitizeCustomerLoyaltyReward,
  type SanitizedCustomerLoyaltyReward,
} from "./loyaltyRewardCatalog";

/**
 * `getCustomerLoyaltyRewardCatalog` — Boncuk Loyalty Program P7-B
 * (2026-08-24).
 *
 * The sole customer-facing read path for the Reward Catalog. Mirrors
 * `getCustomerLoyaltySnapshot.ts`'s exact identity/tenant discipline:
 * real-phone-customer required, `organizationId` resolved exclusively via
 * [SINGLE_TENANT_ORGANIZATION_ID] (never client-supplied — there is no
 * field on `request.data` for it, matching Correction A), tenant
 * membership independently re-verified server-side via the Admin SDK.
 *
 * **Why a callable, not a direct Firestore read.** `loyaltyRewardCatalog`
 * has no `firestore.rules` read rule at all (see that file's own P7-B
 * comment) — the P7-A audit's own precedent (`getReservationBranchInfo`
 * serving `reservationAreas`/`reservationPolicies`, neither of which has a
 * client-read rule either) is that server-computed/filtered reference data
 * is served via a callable, never a raw client query, whenever real
 * filtering logic (here: active/archived/validity-window/tenant) is
 * involved — encoding that filter correctly and safely in rules language
 * would duplicate this exact logic in two places for no benefit.
 *
 * **Query shape, deliberately conservative.** Only equality filters
 * (`organizationId`/`active`/`archived`) are sent to Firestore — no
 * `orderBy`/inequality filter, which would require defining a new
 * composite index before any real query needs one (this codebase's own
 * stated indexing policy). `validFrom`/`validUntil` and `sortOrder` are
 * both applied in memory, over what is expected to be a small catalog
 * (tens of rewards, not thousands).
 */

interface GetCustomerLoyaltyRewardCatalogResult {
  rewards: SanitizedCustomerLoyaltyReward[];
}

export const getCustomerLoyaltyRewardCatalog = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request): Promise<GetCustomerLoyaltyRewardCatalogResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "The reward catalog requires a real, phone-verified customer identity.",
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

    const querySnap = await db
      .collection(LOYALTY_REWARD_CATALOG_COLLECTION)
      .where("organizationId", "==", organizationId)
      .where("active", "==", true)
      .where("archived", "==", false)
      .get();

    const now = Timestamp.now();
    const rewards = querySnap.docs
      .map((doc) => parseLoyaltyRewardCatalogEntry(doc.data()))
      .filter((reward): reward is NonNullable<typeof reward> => reward !== null)
      .filter((reward) => isRewardCurrentlyValid(reward, now))
      .sort((a, b) => a.sortOrder - b.sortOrder)
      .map(sanitizeCustomerLoyaltyReward);

    return { rewards };
  },
);
