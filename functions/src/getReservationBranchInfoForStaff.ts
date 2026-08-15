import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore } from "firebase-admin/firestore";
import { requireStaffPermission } from "./staffAuthorization";
import { shouldEnforceAppCheck } from "./appCheckConfig";

/**
 * Faz R.3A — the staff-facing sibling of `getReservationBranchInfo.ts`.
 * That callable is deliberately customer-only (`sign_in_provider ===
 * "phone"`, by its own explicit design) — a staff member signed in via
 * email/password can never satisfy it. `reservationAreas` still has no
 * client read path of any kind (`firestore.rules`'s fail-closed
 * catch-all), so the admin propose-change/calendar-area-filter UI needs
 * its own read model. A small, deliberate duplication of that callable's
 * area-listing query (never the policy/booking-horizon fields customer
 * flow steps need but staff operations don't) — matches this codebase's
 * own established "small independent duplication over a cross-boundary
 * import" precedent (`ReservationPreorderItem`, duplicated between
 * `reservation` and `takeaway`).
 */
export const getReservationBranchInfoForStaff = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    const data = (request.data ?? {}) as Record<string, unknown>;
    if (typeof data.organizationId !== "string" || data.organizationId.length === 0) {
      throw new HttpsError("invalid-argument", "organizationId is required.");
    }
    if (typeof data.branchId !== "string" || data.branchId.length === 0) {
      throw new HttpsError("invalid-argument", "branchId is required.");
    }
    const organizationId = data.organizationId;
    const branchId = data.branchId;

    requireStaffPermission(request, organizationId, "manageReservations");

    const db = getFirestore();
    const branchDoc = await db.collection("branches").doc(branchId).get();
    if (!branchDoc.exists || branchDoc.data()!.organizationId !== organizationId) {
      throw new HttpsError("not-found", "Branch not found.");
    }

    const areasSnapshot = await db
      .collection("reservationAreas")
      .where("branchId", "==", branchId)
      .where("isActive", "==", true)
      .get();
    const areas = areasSnapshot.docs
      .map((doc) => ({
        id: doc.id,
        displayName: String(doc.data().displayName ?? ""),
        sortOrder: typeof doc.data().sortOrder === "number" ? doc.data().sortOrder : 0,
      }))
      .sort((a, b) => a.sortOrder - b.sortOrder)
      .map(({ id, displayName }) => ({ id, displayName }));

    return { areas };
  },
);
