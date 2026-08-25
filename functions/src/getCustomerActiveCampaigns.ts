import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { SINGLE_TENANT_ORGANIZATION_ID, TENANT_CUSTOMERS_COLLECTION } from "./completeCustomerProfile";
import {
  CAMPAIGNS_COLLECTION,
  parseCampaignDefinition,
  isCampaignCurrentlyEligible,
  sanitizeCustomerCampaign,
  type SanitizedCustomerCampaign,
} from "./campaignEngine";
import { DEFAULT_ORGANIZATION_TIMEZONE } from "./campaignScheduling";

/**
 * `getCustomerActiveCampaigns` — Server-Authoritative Campaign Engine P8-B
 * (2026-08-25).
 *
 * The sole customer-facing read path for Campaigns — mirrors
 * `getCustomerLoyaltyRewardCatalog.ts`'s exact shape (real-filtering-via-
 * callable, never a direct client Firestore read; `organizationId` resolved
 * exclusively via [SINGLE_TENANT_ORGANIZATION_ID], never client-supplied).
 *
 * **Deliberately open to BOTH real, phone-verified customers AND anonymous
 * table guests — unlike the Reward Catalog, which is real-customer-only.**
 * Locked decision: "Anonymous table guests may use campaigns ONLY when
 * perCustomerUsageLimit == null." A guest cannot be told a campaign exists
 * only to be denied it at checkout, so the LISTING itself must already be
 * visible to a guest identity — some Firebase Auth session (real or
 * anonymous) is still required (matching the "no unauthenticated callable
 * access anywhere" convention this codebase otherwise holds everywhere),
 * but phone-verification and `tenantCustomers` membership are only checked
 * for a REAL customer identity; an anonymous caller skips both (a guest
 * cannot have a `tenantCustomers` membership record at all — that
 * collection is for registered customers only).
 *
 * **Until a real campaign exists, this always returns an empty list** — by
 * construction, not as a special case: the query simply finds no matching
 * `campaigns` documents. No mock/fallback data is ever substituted.
 *
 * **`timeZone`**: this callable has no specific branch/order context to
 * source a real timezone from, so it uses [DEFAULT_ORGANIZATION_TIMEZONE]
 * (documented in `campaignScheduling.ts` as existing for exactly this
 * reason) — a future checkout-integration phase, which DOES know the real
 * order's branch, must resolve the branch's own real timezone instead.
 *
 * **Query shape, deliberately conservative** — only equality filters
 * (`organizationId`/`active`/`archived`) are sent to Firestore, mirroring
 * `getCustomerLoyaltyRewardCatalog.ts`'s own documented reasoning
 * (equality-only queries need no new composite index; schedule/sort
 * filtering happens in memory over what is expected to be a small
 * catalog).
 */

interface GetCustomerActiveCampaignsResult {
  campaigns: SanitizedCustomerCampaign[];
}

export const getCustomerActiveCampaigns = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request): Promise<GetCustomerActiveCampaignsResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }

    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    const db = getFirestore();

    // Correction A precedent (P1) — never client-supplied; request.data is
    // never read for organizationId.
    const organizationId = SINGLE_TENANT_ORGANIZATION_ID;

    if (isRealCustomer) {
      const membershipSnap = await db
        .collection(TENANT_CUSTOMERS_COLLECTION)
        .doc(`${organizationId}_${request.auth.uid}`)
        .get();
      if (!membershipSnap.exists) {
        throw new HttpsError("permission-denied", "You are not a customer of this organization.");
      }
    }
    // Anonymous (non-phone) callers: no tenant-membership check — a table
    // guest has no `tenantCustomers` record to check, by design.

    const querySnap = await db
      .collection(CAMPAIGNS_COLLECTION)
      .where("organizationId", "==", organizationId)
      .where("active", "==", true)
      .where("archived", "==", false)
      .get();

    const now = Timestamp.now();
    const campaigns = querySnap.docs
      .map((doc) => parseCampaignDefinition(doc.data()))
      .filter((campaign): campaign is NonNullable<typeof campaign> => campaign !== null)
      .filter((campaign) => isCampaignCurrentlyEligible(campaign, now, DEFAULT_ORGANIZATION_TIMEZONE))
      .sort((a, b) => a.sortOrder - b.sortOrder)
      .map(sanitizeCustomerCampaign);

    return { campaigns };
  },
);
