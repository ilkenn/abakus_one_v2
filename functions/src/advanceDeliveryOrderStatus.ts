import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import {
  requireDeliveryOrderId,
  applyDeliveryLifecycleTransition,
  writeDeliveryOrderStatusChangeAuditEvent,
} from "./deliveryOrderLifecycle";

/**
 * `advanceDeliveryOrderStatus` — Boncuk Loyalty Program P5-B (2026-08-24).
 *
 * Advances an already-`confirmed` delivery order through the canonical
 * delivery lifecycle: `confirmed -> preparing -> ready -> outForDelivery ->
 * completed`. **Only the EXACT next status is ever accepted** —
 * `DELIVERY_NEXT_STATUS` is a stricter, delivery-specific allow-list layered
 * on top of (never replacing) the generic `canTransition` table, mirroring
 * `advanceTakeawayOrderStatus.ts` exactly except for the extra
 * `ready -> outForDelivery -> completed` step (takeaway has no
 * "out for delivery" concept; delivery has no "served" concept).
 *
 * **LOCKED semantics (P5-B §5): `ready != completed`, `outForDelivery !=
 * completed` — `completed` means the order was actually delivered to /
 * received by the customer, never merely that the kitchen finished
 * preparing it or that a courier picked it up.** This is what may trigger
 * Boncuk earning (`onOrderCompleted.ts`, unmodified, unaffected by this
 * callable beyond the `status` write itself).
 *
 * Same staff-only authorization as `respondToDeliveryOrder.ts`: server
 * loads the order first, derives `organizationId`/`branchId` from IT (never
 * from client input), requires `manageDeliveryOrders` + branch access. No
 * loyalty write here — a successful `outForDelivery -> completed` transition
 * is picked up automatically by the already-built, unmodified
 * `onOrderCompleted.ts` outbox trigger. **Courier-authoritative delivery
 * completion is deliberately out of scope this phase (P5-B §7) — every step
 * including the final `-> completed` requires `manageDeliveryOrders`
 * (staff/manager/admin/tenantOwner); courier has no lifecycle permission at
 * all.**
 *
 * **AP-6 Sprint 2 addition**: when `targetStatus` is `completed` and the
 * order carries an `assignedCourierId` (`assignCourierToOrder.ts`), this
 * callable ALSO removes the order from that courier's `activeOrderIds`, in
 * the same transaction as the completion transition — the read-before-write
 * discipline above stays unchanged, just with one more conditional
 * read/write pair. Still never flips the courier back to `available`/
 * stamps `returnedAt` — see `markCourierReturned.ts`.
 */

const DELIVERY_NEXT_STATUS: Partial<Record<OrderStatus, OrderStatus>> = {
  confirmed: "preparing",
  preparing: "ready",
  ready: "outForDelivery",
  outForDelivery: "completed",
};
const VALID_TARGET_STATUSES: readonly OrderStatus[] = [
  "preparing",
  "ready",
  "outForDelivery",
  "completed",
];

function requireTargetStatus(raw: unknown): OrderStatus {
  if (typeof raw !== "string" || !VALID_TARGET_STATUSES.includes(raw as OrderStatus)) {
    throw new HttpsError(
      "invalid-argument",
      `targetStatus must be one of: ${VALID_TARGET_STATUSES.join(", ")}.`,
    );
  }
  return raw as OrderStatus;
}

export const advanceDeliveryOrderStatus = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireDeliveryOrderId(data.orderId);
    const targetStatus = requireTargetStatus(data.targetStatus);

    const db = getFirestore();
    const orderRef = db.collection("orders").doc(orderId);

    return db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "Order not found.");
      }
      const order = orderSnap.data()!;

      if (order.channel !== "delivery") {
        throw new HttpsError("failed-precondition", "This order is not a delivery order.");
      }
      const organizationId = order.organizationId as string;
      const branchId = order.branchId as string;

      requireStaffPermission(request, organizationId, "manageDeliveryOrders");
      requireBranchAccess(request, organizationId, branchId);

      const currentStatus = order.status as OrderStatus;

      if (currentStatus === targetStatus) {
        return { orderId, status: currentStatus, duplicate: true };
      }
      const expectedNext = DELIVERY_NEXT_STATUS[currentStatus];
      if (expectedNext !== targetStatus) {
        throw new HttpsError(
          "failed-precondition",
          `Cannot advance from "${currentStatus}" directly to "${targetStatus}" — only the exact next status is allowed, no skipping.`,
        );
      }
      if (!canTransition(currentStatus, targetStatus)) {
        // Defensive only — DELIVERY_NEXT_STATUS is already a strict subset
        // of the generic table, but this callable must never assume a
        // transition it doesn't itself verify.
        throw new HttpsError("failed-precondition", "Transition not allowed.");
      }

      const now = Timestamp.now();
      const actorUid = request.auth!.uid;
      const token = request.auth!.token as Record<string, unknown>;
      const rolesByOrg = token.roles as Record<string, unknown> | undefined;
      const actorRoles = Array.isArray(rolesByOrg?.[organizationId])
        ? (rolesByOrg![organizationId] as string[])
        : null;

      // AP-6 Sprint 2 — the completion-hook read, still in the read phase
      // (before any write below): if this order carries an
      // `assignedCourierId`, release it from that courier's
      // `activeOrderIds` in the SAME transaction as the completion
      // transition, so the two can never drift apart. Deliberately does
      // NOT flip the courier back to `available`/stamp `returnedAt` — see
      // `markCourierReturned.ts`'s own doc comment for why that stays a
      // separate, physical-return confirmation.
      const assignedCourierId = order.assignedCourierId as string | undefined;
      const courierRef =
        targetStatus === "completed" && assignedCourierId
          ? db.collection("couriers").doc(assignedCourierId)
          : null;
      const courierSnap = courierRef ? await tx.get(courierRef) : null;

      applyDeliveryLifecycleTransition({
        tx,
        orderRef,
        orderId,
        order,
        fromStatus: currentStatus,
        toStatus: targetStatus,
        actorType: "staff",
        now,
      });
      writeDeliveryOrderStatusChangeAuditEvent({
        tx,
        db,
        orderId,
        organizationId,
        branchId,
        fromStatus: currentStatus,
        toStatus: targetStatus,
        actorType: "staff",
        actorUid,
        actorRoles,
        now,
      });

      if (courierRef && courierSnap && courierSnap.exists) {
        const courier = courierSnap.data()!;
        const activeOrderIds: string[] = Array.isArray(courier.activeOrderIds)
          ? courier.activeOrderIds
          : [];
        tx.set(
          courierRef,
          {
            activeOrderIds: activeOrderIds.filter((id) => id !== orderId),
            updatedAt: now,
            revision: (Number(courier.revision) || 1) + 1,
          },
          { merge: true },
        );
      }

      return { orderId, status: targetStatus, duplicate: false };
    });
  },
);
