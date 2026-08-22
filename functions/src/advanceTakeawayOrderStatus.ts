import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import {
  requireTakeawayOrderId,
  applyTakeawayLifecycleTransition,
  writeTakeawayOrderStatusChangeAuditEvent,
} from "./takeawayOrderLifecycle";

/**
 * `advanceTakeawayOrderStatus` — Boncuk Loyalty Program P4-C-C-B
 * (2026-08-22).
 *
 * Advances an already-`confirmed` takeaway order through the kitchen
 * lifecycle: `confirmed -> preparing -> ready -> completed`. **Only the
 * EXACT next status is ever accepted** — `TAKEAWAY_NEXT_STATUS` below is
 * deliberately a stricter, takeaway-specific allow-list layered on top of
 * (never replacing) the generic `canTransition` table, since that table
 * alone would also permit `ready -> outForDelivery`/`ready -> served`
 * (delivery/dine-in concepts that never apply to takeaway) and says
 * nothing at all about "no skipping" — `confirmed -> completed` must fail
 * even though nothing in the generic graph forbids it a priori for other
 * channels' own shapes.
 *
 * **`ready -> completed` is the fulfillment event — LOCKED semantic
 * (P4-C-C-A §10/P4-C-C-B §1): `completed` means the order was actually
 * handed to / received by the customer, not merely that the kitchen
 * finished preparing it.** This is what may trigger Boncuk earning
 * (`onOrderCompleted.ts`, unmodified, unaffected by this callable beyond
 * the `status` write itself) — the eventual staff UI (out of scope this
 * phase) must present this specific step as a deliberate "confirm handed
 * to customer" action, never a generic "next" button.
 *
 * Same staff-only authorization as `respondToTakeawayOrder.ts`: server
 * loads the order first, derives `organizationId`/`branchId` from IT
 * (never from client input), requires `manageTakeawayOrders` + branch
 * access. No loyalty write here — a successful `ready -> completed`
 * transition is picked up automatically by the already-built, unmodified
 * `onOrderCompleted.ts` outbox trigger.
 */

const TAKEAWAY_NEXT_STATUS: Partial<Record<OrderStatus, OrderStatus>> = {
  confirmed: "preparing",
  preparing: "ready",
  ready: "completed",
};
const VALID_TARGET_STATUSES: readonly OrderStatus[] = ["preparing", "ready", "completed"];

function requireTargetStatus(raw: unknown): OrderStatus {
  if (typeof raw !== "string" || !VALID_TARGET_STATUSES.includes(raw as OrderStatus)) {
    throw new HttpsError(
      "invalid-argument",
      `targetStatus must be one of: ${VALID_TARGET_STATUSES.join(", ")}.`,
    );
  }
  return raw as OrderStatus;
}

export const advanceTakeawayOrderStatus = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireTakeawayOrderId(data.orderId);
    const targetStatus = requireTargetStatus(data.targetStatus);

    const db = getFirestore();
    const orderRef = db.collection("orders").doc(orderId);

    return db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "Order not found.");
      }
      const order = orderSnap.data()!;

      if (order.channel !== "takeaway") {
        throw new HttpsError("failed-precondition", "This order is not a takeaway order.");
      }
      const organizationId = order.organizationId as string;
      const branchId = order.branchId as string;

      requireStaffPermission(request, organizationId, "manageTakeawayOrders");
      requireBranchAccess(request, organizationId, branchId);

      const currentStatus = order.status as OrderStatus;

      if (currentStatus === targetStatus) {
        return { orderId, status: currentStatus, duplicate: true };
      }
      const expectedNext = TAKEAWAY_NEXT_STATUS[currentStatus];
      if (expectedNext !== targetStatus) {
        throw new HttpsError(
          "failed-precondition",
          `Cannot advance from "${currentStatus}" directly to "${targetStatus}" — only the exact next status is allowed, no skipping.`,
        );
      }
      if (!canTransition(currentStatus, targetStatus)) {
        // Defensive only — TAKEAWAY_NEXT_STATUS is already a strict subset
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

      applyTakeawayLifecycleTransition({
        tx,
        orderRef,
        orderId,
        order,
        fromStatus: currentStatus,
        toStatus: targetStatus,
        actorType: "staff",
        now,
      });
      writeTakeawayOrderStatusChangeAuditEvent({
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

      return { orderId, status: targetStatus, duplicate: false };
    });
  },
);
