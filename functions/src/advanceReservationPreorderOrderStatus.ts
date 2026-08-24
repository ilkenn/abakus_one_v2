import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireReservationManagerPermission } from "./reservationAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import {
  requireReservationPreorderOrderId,
  applyReservationPreorderOrderLifecycleTransition,
  writeReservationPreorderOrderStatusChangeAuditEvent,
} from "./reservationPreorderOrderLifecycle";

/**
 * `advanceReservationPreorderOrderStatus` — Boncuk Loyalty Program P6-B
 * (2026-08-24).
 *
 * Advances an already-`confirmed` (released-to-kitchen) reservation
 * preorder order through the kitchen lifecycle: `confirmed -> preparing ->
 * ready -> served -> completed`. **Only the EXACT next status is ever
 * accepted** — `RESERVATION_PREORDER_NEXT_STATUS` below is a stricter,
 * channel-specific allow-list layered on top of (never replacing) the
 * generic `canTransition` table, mirroring `advanceTakeawayOrderStatus.ts`/
 * `advanceDeliveryOrderStatus.ts` exactly. This channel's own chain has one
 * extra step versus takeaway's `confirmed→preparing→ready→completed`
 * (`served` sits between `ready` and `completed` — a reservation preorder
 * is handed to a seated guest, mirroring dine-in's own `served` concept,
 * never takeaway's direct hand-off) and takes a different path than
 * delivery's `outForDelivery` step (a reservation preorder never leaves the
 * restaurant).
 *
 * **LOCKED semantic (P6-B §4): `completed` means the order was actually
 * served to / received by the guest, not merely that the kitchen finished
 * preparing it.** This is what may trigger Boncuk earning
 * (`onOrderCompleted.ts`, unmodified) — `reservationPreorder` has been in
 * `LOYALTY_EARNING_ELIGIBLE_CHANNELS` since P2A but was structurally
 * unreachable until this callable existed (P6-A's proven gap).
 *
 * Authorization mirrors every other reservation-domain callable
 * (`respondToReservation.ts`/`completeReservation.ts`/
 * `markReservationNoShow.ts`) — the single `manageReservations` permission,
 * org-scoped only, via `requireReservationManagerPermission`. Deliberately
 * NOT the takeaway/delivery-style tiered permission model (no escalated
 * tier was requested for this channel, and reservations have never used
 * that model) — the same staff who already manage reservation confirm/
 * reject/complete/no-show are exactly the ones who run this channel's
 * kitchen operations too.
 */

const RESERVATION_PREORDER_NEXT_STATUS: Partial<Record<OrderStatus, OrderStatus>> = {
  confirmed: "preparing",
  preparing: "ready",
  ready: "served",
  served: "completed",
};
const VALID_TARGET_STATUSES: readonly OrderStatus[] = ["preparing", "ready", "served", "completed"];

function requireTargetStatus(raw: unknown): OrderStatus {
  if (typeof raw !== "string" || !VALID_TARGET_STATUSES.includes(raw as OrderStatus)) {
    throw new HttpsError(
      "invalid-argument",
      `targetStatus must be one of: ${VALID_TARGET_STATUSES.join(", ")}.`,
    );
  }
  return raw as OrderStatus;
}

export const advanceReservationPreorderOrderStatus = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireReservationPreorderOrderId(data.orderId);
    const targetStatus = requireTargetStatus(data.targetStatus);

    const db = getFirestore();
    const orderRef = db.collection("orders").doc(orderId);

    return db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "Order not found.");
      }
      const order = orderSnap.data()!;

      if (order.channel !== "reservationPreorder") {
        throw new HttpsError("failed-precondition", "This order is not a reservation preorder order.");
      }
      const organizationId = order.organizationId as string;

      requireReservationManagerPermission(request, organizationId);

      const currentStatus = order.status as OrderStatus;

      if (currentStatus === targetStatus) {
        return { orderId, status: currentStatus, duplicate: true };
      }
      const expectedNext = RESERVATION_PREORDER_NEXT_STATUS[currentStatus];
      if (expectedNext !== targetStatus) {
        throw new HttpsError(
          "failed-precondition",
          `Cannot advance from "${currentStatus}" directly to "${targetStatus}" — only the exact next status is allowed, no skipping.`,
        );
      }
      if (!canTransition(currentStatus, targetStatus)) {
        // Defensive only — TAKEAWAY_NEXT_STATUS-style maps are already a
        // strict subset of the generic table, but this callable must never
        // assume a transition it doesn't itself verify.
        throw new HttpsError("failed-precondition", "Transition not allowed.");
      }

      const now = Timestamp.now();
      const actorUid = request.auth!.uid;
      const token = request.auth!.token as Record<string, unknown>;
      const rolesByOrg = token.roles as Record<string, unknown> | undefined;
      const actorRoles = Array.isArray(rolesByOrg?.[organizationId])
        ? (rolesByOrg![organizationId] as string[])
        : null;

      applyReservationPreorderOrderLifecycleTransition({
        tx,
        orderRef,
        orderId,
        order,
        fromStatus: currentStatus,
        toStatus: targetStatus,
        actorType: "staff",
        now,
      });
      writeReservationPreorderOrderStatusChangeAuditEvent({
        tx,
        db,
        orderId,
        organizationId,
        branchId: order.branchId as string,
        fromStatus: currentStatus,
        toStatus: targetStatus,
        actorType: "staff",
        actorUid,
        actorRoles,
        now,
      });

      return { orderId, status: targetStatus, duplicate: false };
    });
  },
);
