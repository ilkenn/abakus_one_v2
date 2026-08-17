import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { resolveDeliveryServiceArea, slugifyAddressComponent } from "./deliveryServiceAreas";

/**
 * Read-only, ADVISORY eligibility check for the Paket Servis checkout UI —
 * P.3. Lets the customer see "Bu adrese şu anda paket servis hizmeti
 * veremiyoruz." / minimum-order messaging before attempting a real
 * submission, per the approved architecture's D2.
 *
 * **Never authorization.** `submitDeliveryOrder` independently re-reads and
 * re-validates everything this callable checks — an earlier eligible
 * result here is never trusted as proof of anything at submit time. This
 * callable exists purely to avoid a jarring failure at the very last step
 * of checkout; it has no side effects and creates nothing.
 */

interface CheckDeliveryEligibilityResult {
  eligible: boolean;
  reason: "address_not_verified" | "not_covered" | "ambiguous_configuration" | null;
  minimumOrderMinorUnits: number | null;
}

export const checkDeliveryEligibility = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request): Promise<CheckDeliveryEligibilityResult> => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const isRealCustomer = request.auth.token?.firebase?.sign_in_provider === "phone";
    if (!isRealCustomer) {
      throw new HttpsError(
        "permission-denied",
        "A real, phone-verified customer identity is required.",
      );
    }

    const savedAddressId = request.data?.savedAddressId;
    if (typeof savedAddressId !== "string" || savedAddressId.length === 0) {
      throw new HttpsError("invalid-argument", "savedAddressId is required.");
    }

    const db = getFirestore();
    const addressDoc = await db.collection("customerAddresses").doc(savedAddressId).get();
    if (!addressDoc.exists) {
      throw new HttpsError("not-found", "No such address.");
    }
    const address = addressDoc.data()!;
    if (address.uid !== request.auth.uid) {
      throw new HttpsError("permission-denied", "This address does not belong to the caller.");
    }
    if (address.verificationStatus !== "verified") {
      return { eligible: false, reason: "address_not_verified", minimumOrderMinorUnits: null };
    }

    const districtId = slugifyAddressComponent(String(address.districtName ?? ""));
    const neighborhoodId = slugifyAddressComponent(String(address.neighborhoodName ?? ""));
    const result = await resolveDeliveryServiceArea(db, { districtId, neighborhoodId });

    if (result.status === "notCovered") {
      return { eligible: false, reason: "not_covered", minimumOrderMinorUnits: null };
    }
    if (result.status === "ambiguous") {
      return { eligible: false, reason: "ambiguous_configuration", minimumOrderMinorUnits: null };
    }
    return {
      eligible: true,
      reason: null,
      minimumOrderMinorUnits: result.area.minimumOrderMinorUnits,
    };
  },
);
