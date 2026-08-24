import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import {
  requireDineInOrderId,
  sanitizeDineInRejectionReasonCode,
  sanitizeDineInCancellationReasonCode,
  sanitizeOptionalReasonMessage,
  applyDineInLifecycleTransition,
  writeDineInOrderStatusChangeAuditEvent,
} from "./dineInOrderLifecycle";

/**
 * `advanceDineInOrderStatus` — Boncuk Loyalty Program P7-D.1 (2026-08-24).
 *
 * The minimum server-authoritative lifecycle primitive dine-in needs to
 * safely support Loyalty restore/earning (BR-LOYALTY-029's own audit
 * finding: no dine-in lifecycle Cloud Function existed at all before this
 * phase) — deliberately NOT a broad POS lifecycle rebuild. **One callable
 * consolidates what takeaway/delivery split across three
 * (`respondToXOrder`/`advanceXOrderStatus`/`cancelXOrderForStaff`)** —
 * confirm, reject, kitchen-advance, and pre-completion cancel all go
 * through this single `targetStatus`-driven entry point, under one
 * `manageDineInOrders` permission (no separate escalated-cancellation
 * tier yet, unlike takeaway/delivery — can be layered on later without a
 * callable redesign). Refund is deliberately its OWN separate callable
 * (`refundDineInOrder.ts`), matching every other channel's own dedicated-
 * permission boundary for that specific, more consequential action.
 *
 * Chain: `pendingConfirmation -> confirmed -> preparing -> ready -> served
 * -> completed` — mirrors `reservationPreorder`'s own kitchen chain
 * exactly (the `served` step between `ready` and `completed` is the same
 * dine-in-shaped concept both channels share). `pendingConfirmation ->
 * rejected` is a restaurant refusal before ever accepting; `confirmed`/
 * `preparing`/`ready`/`served` `-> cancelled` is a cancellation of an
 * already-accepted order. Only the EXACT next status is ever accepted for
 * a forward advance — no skipping.
 *
 * **No loyalty write here, by design.** A successful `completed`
 * transition is picked up automatically by the already-built, unmodified
 * `onOrderCompleted.ts` outbox trigger (now that `dineInQr` is in
 * `LOYALTY_EARNING_ELIGIBLE_CHANNELS`); `rejected`/`cancelled` are picked
 * up by `onOrderTerminalFailureOrRefund.ts` for catalog-reward restore —
 * writing `status` is all this callable ever needs to do.
 */

const DINE_IN_NEXT_STATUS: Partial<Record<OrderStatus, OrderStatus>> = {
  confirmed: "preparing",
  preparing: "ready",
  ready: "served",
  served: "completed",
};
const CANCELLABLE_FROM: readonly OrderStatus[] = ["confirmed", "preparing", "ready", "served"];
const VALID_TARGET_STATUSES: readonly OrderStatus[] = [
  "confirmed",
  "rejected",
  "preparing",
  "ready",
  "served",
  "completed",
  "cancelled",
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

export const advanceDineInOrderStatus = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireDineInOrderId(data.orderId);
    const targetStatus = requireTargetStatus(data.targetStatus);
    const reasonCode =
      targetStatus === "rejected"
        ? sanitizeDineInRejectionReasonCode(data.reasonCode)
        : targetStatus === "cancelled"
          ? sanitizeDineInCancellationReasonCode(data.reasonCode)
          : null;
    const reasonMessage =
      targetStatus === "rejected" || targetStatus === "cancelled"
        ? sanitizeOptionalReasonMessage(data.reasonMessage)
        : null;

    const db = getFirestore();
    const orderRef = db.collection("orders").doc(orderId);

    return db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "Order not found.");
      }
      const order = orderSnap.data()!;

      if (order.channel !== "dineInQr") {
        throw new HttpsError("failed-precondition", "This order is not a dine-in order.");
      }
      const organizationId = order.organizationId as string;
      const branchId = order.branchId as string;

      requireStaffPermission(request, organizationId, "manageDineInOrders");
      requireBranchAccess(request, organizationId, branchId);

      const currentStatus = order.status as OrderStatus;

      if (currentStatus === targetStatus) {
        return { orderId, status: currentStatus, duplicate: true };
      }

      if (targetStatus === "confirmed" || targetStatus === "rejected") {
        if (currentStatus !== "pendingConfirmation") {
          throw new HttpsError(
            "failed-precondition",
            `Order is not pendingConfirmation (current status: "${String(currentStatus)}").`,
          );
        }
      } else if (targetStatus === "cancelled") {
        if (currentStatus === "pendingConfirmation") {
          throw new HttpsError(
            "failed-precondition",
            'A pendingConfirmation order cannot be cancelled here — use targetStatus: "rejected" instead.',
          );
        }
        if (!CANCELLABLE_FROM.includes(currentStatus)) {
          throw new HttpsError(
            "failed-precondition",
            `Order cannot be cancelled from status "${currentStatus}".`,
          );
        }
      } else {
        const expectedNext = DINE_IN_NEXT_STATUS[currentStatus];
        if (expectedNext !== targetStatus) {
          throw new HttpsError(
            "failed-precondition",
            `Cannot advance from "${currentStatus}" directly to "${targetStatus}" — only the exact next status is allowed, no skipping.`,
          );
        }
      }
      if (!canTransition(currentStatus, targetStatus)) {
        // Defensive only — every branch above already guarantees this, but
        // this callable must never assume a transition it doesn't itself
        // verify.
        throw new HttpsError("failed-precondition", "Transition not allowed.");
      }

      const now = Timestamp.now();
      const actorUid = request.auth!.uid;
      const token = request.auth!.token as Record<string, unknown>;
      const rolesByOrg = token.roles as Record<string, unknown> | undefined;
      const actorRoles = Array.isArray(rolesByOrg?.[organizationId])
        ? (rolesByOrg![organizationId] as string[])
        : null;

      const isTerminal = targetStatus === "rejected" || targetStatus === "cancelled";

      applyDineInLifecycleTransition({
        tx,
        orderRef,
        orderId,
        order,
        fromStatus: currentStatus,
        toStatus: targetStatus,
        actorType: "staff",
        now,
        terminalReasonCode: isTerminal ? reasonCode : null,
      });
      writeDineInOrderStatusChangeAuditEvent({
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
        reasonCode: isTerminal ? reasonCode : null,
        reasonMessage: isTerminal ? reasonMessage : null,
        now,
      });

      return { orderId, status: targetStatus, duplicate: false };
    });
  },
);
