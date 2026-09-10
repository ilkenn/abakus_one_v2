import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";

/**
 * AP-6 Sprint 2 — confirms a courier's physical return to the branch,
 * flipping `dispatchStatus: "available"` and stamping `returnedAt` (the
 * FIFO dispatch sort key, `courier_return_fifo.dart`).
 *
 * **Deliberately a separate, explicit staff confirmation — never
 * auto-triggered by an order reaching `completed`.** "Delivered the last
 * package" is a *system* event (`advanceDeliveryOrderStatus.ts`'s own
 * completion hook only removes the order from `activeOrderIds`); "back at
 * the branch" is a *physical* event a courier can lag behind by several
 * minutes. Rejects (`failed-precondition`) if `activeOrderIds` is still
 * non-empty — a courier cannot be marked available while a delivery is
 * still logged as out.
 */

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value;
}

export const markCourierReturned = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const courierId = requireString(data.courierId, "courierId");

    const db = getFirestore();
    const courierRef = db.collection("couriers").doc(courierId);

    return db.runTransaction(async (tx) => {
      const courierSnap = await tx.get(courierRef);
      if (!courierSnap.exists) {
        throw new HttpsError("not-found", "Courier not found.");
      }
      const courier = courierSnap.data()!;
      const organizationId = courier.organizationId as string;
      const branchId = courier.branchId as string;

      requireStaffPermission(request, organizationId, "manageCourierDispatch");
      requireBranchAccess(request, organizationId, branchId);

      const activeOrderIds: string[] = Array.isArray(courier.activeOrderIds)
        ? courier.activeOrderIds
        : [];
      if (activeOrderIds.length > 0) {
        throw new HttpsError(
          "failed-precondition",
          "This courier still has active deliveries out — cannot mark as returned until every delivery is completed.",
        );
      }

      const now = Timestamp.now();
      tx.set(
        courierRef,
        {
          dispatchStatus: "available",
          returnedAt: now,
          updatedAt: now,
          revision: (Number(courier.revision) || 1) + 1,
        },
        { merge: true },
      );

      return { courierId, dispatchStatus: "available" };
    });
  },
);
