import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import {
  requireTakeawayOrderId,
  sanitizeCancellationReasonCode,
  sanitizeOptionalReasonMessage,
  applyTakeawayLifecycleTransition,
  writeTakeawayOrderStatusChangeAuditEvent,
} from "./takeawayOrderLifecycle";
import { prepareCancellationStockHandling, applyCancellationStockHandling } from "./cancelOrderLineStock";

/**
 * `cancelTakeawayOrderForStaff` — Boncuk Loyalty Program P4-C-C-B
 * (2026-08-22).
 *
 * Staff/manager/admin cancellation of an ALREADY-ACCEPTED takeaway order —
 * `confirmed -> cancelled`, `preparing -> cancelled`, `ready -> cancelled`.
 * **`pendingConfirmation` is explicitly rejected here** — restaurant
 * refusal of an order that was never accepted must go through
 * `respondToTakeawayOrder(decision: "reject")` instead (P4-C-C-A §2/§5's
 * locked REJECTED-vs-CANCELLED distinction). `completed` is also denied —
 * a fulfilled order cannot be cancelled (a future refund flow, out of
 * scope, is the only way to undo a completed order).
 *
 * **Escalating authority by kitchen commitment (P4-C-C-A §9, Model B,
 * accepted)**: cancelling a `confirmed` order (before any kitchen prep
 * time/inventory has been committed) requires only `manageTakeawayOrders`
 * — the same baseline permission `respondToTakeawayOrder`/
 * `advanceTakeawayOrderStatus` already require, and the one `staff` role
 * now holds. Cancelling `preparing`/`ready` (real food/inventory/labor
 * already spent) additionally requires `manageTakeawayOrderCancellations`
 * — manager-tier and above only, `staff` is deliberately excluded. The
 * baseline `manageTakeawayOrders` + branch check is verified FIRST,
 * unconditionally, before any status-specific branching — an unauthorized
 * caller is never told anything about the order's actual status.
 *
 * `reasonCode` is REQUIRED (a closed, server-validated enum) — an
 * operational cancellation must always carry a reason. `reasonMessage` is
 * an OPTIONAL, internal-only staff note, written to `auditEvents` alone,
 * never to the customer-readable order document.
 *
 * **No loyalty write here, by design.** A successful `cancelled`
 * transition is picked up automatically by the already-built, unmodified
 * `onOrderTerminalFailureOrRefund.ts` trigger.
 */
export const cancelTakeawayOrderForStaff = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireTakeawayOrderId(data.orderId);
    const reasonCode = sanitizeCancellationReasonCode(data.reasonCode);
    const reasonMessage = sanitizeOptionalReasonMessage(data.reasonMessage);

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

      // Baseline authorization, unconditional — established before any
      // status-specific branching, so an unauthorized caller learns
      // nothing about the order's actual current status.
      requireStaffPermission(request, organizationId, "manageTakeawayOrders");
      requireBranchAccess(request, organizationId, branchId);

      const currentStatus = order.status as OrderStatus;

      if (currentStatus === "cancelled") {
        return { orderId, status: "cancelled", duplicate: true };
      }
      if (currentStatus === "pendingConfirmation") {
        throw new HttpsError(
          "failed-precondition",
          'A pendingConfirmation order cannot be cancelled here — use respondToTakeawayOrder with decision: "reject" instead.',
        );
      }
      if (currentStatus === "completed") {
        throw new HttpsError("failed-precondition", "A completed order cannot be cancelled.");
      }
      if (currentStatus !== "confirmed" && currentStatus !== "preparing" && currentStatus !== "ready") {
        throw new HttpsError(
          "failed-precondition",
          `Order cannot be cancelled from status "${currentStatus}".`,
        );
      }
      if (currentStatus === "preparing" || currentStatus === "ready") {
        // Escalated authority — real kitchen commitment already made.
        requireStaffPermission(request, organizationId, "manageTakeawayOrderCancellations");
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
      // first write (`applyTakeawayLifecycleTransition` below). Takeaway
      // has no per-line cancellation (unlike dine-in) — the whole order is
      // cancelled at once, so every line's own `kitchenWorkItem` is
      // checked, each reversed or wasted independently based on its real
      // status.
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

      applyTakeawayLifecycleTransition({
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
      writeTakeawayOrderStatusChangeAuditEvent({
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
