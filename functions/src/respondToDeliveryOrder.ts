import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import {
  requireDeliveryOrderId,
  sanitizeDeliveryRejectionReasonCode,
  sanitizeOptionalReasonMessage,
  applyDeliveryLifecycleTransition,
  writeDeliveryOrderStatusChangeAuditEvent,
} from "./deliveryOrderLifecycle";

/**
 * `respondToDeliveryOrder` — Boncuk Loyalty Program P5-B (2026-08-24).
 *
 * The canonical, server-authoritative restaurant response to a
 * `pendingConfirmation` delivery order — `confirmed` (accept) or `rejected`
 * (refuse before ever accepting). Mirrors `respondToTakeawayOrder.ts`
 * exactly, using the shared `./deliveryOrderLifecycle` helpers (themselves
 * thin re-exports of the channel-generic `./orderLifecycle` module) and the
 * dedicated `manageDeliveryOrders` permission instead of takeaway's own.
 */
const DECISIONS = ["confirm", "reject"] as const;
type Decision = (typeof DECISIONS)[number];
function sanitizeDecision(raw: unknown): Decision {
  if (typeof raw !== "string" || !(DECISIONS as readonly string[]).includes(raw)) {
    throw new HttpsError("invalid-argument", `decision must be one of: ${DECISIONS.join(", ")}.`);
  }
  return raw as Decision;
}

export const respondToDeliveryOrder = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireDeliveryOrderId(data.orderId);
    const decision = sanitizeDecision(data.decision);
    const reasonCode = decision === "reject" ? sanitizeDeliveryRejectionReasonCode(data.reasonCode) : null;
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

      requireStaffPermission(request, organizationId, "manageDeliveryOrders");
      requireBranchAccess(request, organizationId, branchId);

      const targetStatus: OrderStatus = decision === "confirm" ? "confirmed" : "rejected";
      const currentStatus = order.status as OrderStatus;

      if (currentStatus === targetStatus) {
        return { orderId, status: targetStatus, duplicate: true };
      }
      if (currentStatus !== "pendingConfirmation") {
        throw new HttpsError(
          "failed-precondition",
          `Order is not pending confirmation (current status: "${String(currentStatus)}").`,
        );
      }
      if (!canTransition("pendingConfirmation", targetStatus)) {
        throw new HttpsError("failed-precondition", "Transition not allowed.");
      }

      const now = Timestamp.now();
      const actorUid = request.auth!.uid;
      const token = request.auth!.token as Record<string, unknown>;
      const rolesByOrg = token.roles as Record<string, unknown> | undefined;
      const actorRoles = Array.isArray(rolesByOrg?.[organizationId])
        ? (rolesByOrg![organizationId] as string[])
        : null;

      applyDeliveryLifecycleTransition({
        tx,
        orderRef,
        orderId,
        order,
        fromStatus: "pendingConfirmation",
        toStatus: targetStatus,
        actorType: "staff",
        now,
        terminalReasonCode: decision === "reject" ? reasonCode : null,
      });
      writeDeliveryOrderStatusChangeAuditEvent({
        tx,
        db,
        orderId,
        organizationId,
        branchId,
        fromStatus: "pendingConfirmation",
        toStatus: targetStatus,
        actorType: "staff",
        actorUid,
        actorRoles,
        reasonCode,
        reasonMessage,
        now,
      });

      return { orderId, status: targetStatus, duplicate: false };
    });
  },
);
