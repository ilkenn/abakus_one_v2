import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import {
  requireDeliveryOrderId,
  sanitizeDeliveryCancellationReasonCode,
  sanitizeOptionalReasonMessage,
  applyDeliveryLifecycleTransition,
  writeDeliveryOrderStatusChangeAuditEvent,
} from "./deliveryOrderLifecycle";
import { prepareCancellationStockHandling, applyCancellationStockHandling } from "./cancelOrderLineStock";

/**
 * `cancelDeliveryOrderForStaff` — Boncuk Loyalty Program P5-B (2026-08-24).
 *
 * Staff/manager/admin cancellation of an ALREADY-ACCEPTED delivery order —
 * `confirmed -> cancelled`, `preparing -> cancelled`, `ready -> cancelled`,
 * `outForDelivery -> cancelled`. **`pendingConfirmation` is explicitly
 * rejected here** — restaurant refusal of an order that was never accepted
 * must go through `respondToDeliveryOrder(decision: "reject")` instead
 * (mirrors takeaway's locked REJECTED-vs-CANCELLED distinction). `completed`
 * is also denied — a fulfilled order cannot be cancelled (only
 * `refundDeliveryOrder` can undo a completed order).
 *
 * **Escalating authority by operational commitment (mirrors
 * `cancelTakeawayOrderForStaff.ts` exactly, with one extra escalated status
 * — `outForDelivery`)**: cancelling a `confirmed` order (before any kitchen
 * prep time/inventory has been committed) requires only
 * `manageDeliveryOrders` — the same baseline permission
 * `respondToDeliveryOrder`/`advanceDeliveryOrderStatus` already require, and
 * the one `staff` role now holds. Cancelling `preparing`/`ready`/
 * `outForDelivery` (real food/inventory/labor already spent, or the order is
 * already out with a courier) additionally requires
 * `manageDeliveryOrderCancellations` — manager-tier and above only, `staff`
 * is deliberately excluded. The baseline `manageDeliveryOrders` + branch
 * check is verified FIRST, unconditionally, before any status-specific
 * branching — an unauthorized caller is never told anything about the
 * order's actual status.
 *
 * `reasonCode` is REQUIRED (a closed, server-validated enum) — an
 * operational cancellation must always carry a reason. `reasonMessage` is an
 * OPTIONAL, internal-only staff note, written to `auditEvents` alone, never
 * to the customer-readable order document.
 *
 * **No loyalty write here, by design.** A successful `cancelled` transition
 * is picked up automatically by the already-built, unmodified
 * `onOrderTerminalFailureOrRefund.ts` trigger.
 */
export const cancelDeliveryOrderForStaff = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireDeliveryOrderId(data.orderId);
    const reasonCode = sanitizeDeliveryCancellationReasonCode(data.reasonCode);
    const reasonMessage = sanitizeOptionalReasonMessage(data.reasonMessage);

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

      // Baseline authorization, unconditional — established before any
      // status-specific branching, so an unauthorized caller learns
      // nothing about the order's actual current status.
      requireStaffPermission(request, organizationId, "manageDeliveryOrders");
      requireBranchAccess(request, organizationId, branchId);

      const currentStatus = order.status as OrderStatus;

      if (currentStatus === "cancelled") {
        return { orderId, status: "cancelled", duplicate: true };
      }
      if (currentStatus === "pendingConfirmation") {
        throw new HttpsError(
          "failed-precondition",
          'A pendingConfirmation order cannot be cancelled here — use respondToDeliveryOrder with decision: "reject" instead.',
        );
      }
      if (currentStatus === "completed") {
        throw new HttpsError("failed-precondition", "A completed order cannot be cancelled.");
      }
      if (
        currentStatus !== "confirmed" &&
        currentStatus !== "preparing" &&
        currentStatus !== "ready" &&
        currentStatus !== "outForDelivery"
      ) {
        throw new HttpsError(
          "failed-precondition",
          `Order cannot be cancelled from status "${currentStatus}".`,
        );
      }
      if (
        currentStatus === "preparing" ||
        currentStatus === "ready" ||
        currentStatus === "outForDelivery"
      ) {
        // Escalated authority — real kitchen/courier commitment already made.
        requireStaffPermission(request, organizationId, "manageDeliveryOrderCancellations");
      }
      if (!canTransition(currentStatus, "cancelled")) {
        throw new HttpsError("failed-precondition", "Transition not allowed.");
      }

      const now = Timestamp.now();
      const actorUid = request.auth!.uid;
      const token = request.auth!.token as Record<string, unknown>;
      const rolesByOrg = token.roles as Record<string, unknown> | undefined;
      const actorRoles = Array.isArray(rolesByOrg?.[organizationId])
        ? (rolesByOrg![organizationId] as string[])
        : null;

      // AP-5 Sprint 3 — read phase must run BEFORE this transaction's
      // first write (`applyDeliveryLifecycleTransition` below), mirroring
      // `cancelTakeawayOrderForStaff.ts`'s own fix exactly. Delivery has no
      // per-line cancellation either — every line's own `kitchenWorkItem`
      // is checked independently (an order can be `outForDelivery` while
      // its food was already `ready`/`preparing`).
      const orderLines = Array.isArray(order.lines) ? order.lines : [];
      const stockPlan = await prepareCancellationStockHandling({
        tx,
        db,
        organizationId,
        branchId,
        orderId,
        orderLineIds: orderLines.map((_: unknown, index: number) => `kt-${orderId}-line-${index}`),
        performedByUid: actorUid,
        now,
      });

      applyDeliveryLifecycleTransition({
        tx,
        orderRef,
        orderId,
        order,
        fromStatus: currentStatus,
        toStatus: "cancelled",
        actorType: "staff",
        now,
        terminalReasonCode: reasonCode,
      });
      writeDeliveryOrderStatusChangeAuditEvent({
        tx,
        db,
        orderId,
        organizationId,
        branchId,
        fromStatus: currentStatus,
        toStatus: "cancelled",
        actorType: "staff",
        actorUid,
        actorRoles,
        reasonCode,
        reasonMessage,
        now,
      });
      applyCancellationStockHandling(tx, db, stockPlan);

      return { orderId, status: "cancelled", duplicate: false };
    });
  },
);
