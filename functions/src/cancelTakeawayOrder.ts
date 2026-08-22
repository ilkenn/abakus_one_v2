import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { canTransition } from "./orderStatus";
import {
  requireTakeawayOrderId,
  requireRealCustomer,
  applyTakeawayLifecycleTransition,
  writeTakeawayOrderStatusChangeAuditEvent,
} from "./takeawayOrderLifecycle";

/**
 * `cancelTakeawayOrder` — Boncuk Loyalty Program P4-C-C-B (2026-08-22).
 *
 * The CUSTOMER's own cancellation of their own takeaway order — only ever
 * while `pendingConfirmation`. **No staff authorization branch at all** —
 * this callable is deliberately narrower than `cancelReservation.ts`'s own
 * dual customer/staff actor resolution; staff cancellation is a wholly
 * separate callable, `cancelTakeawayOrderForStaff.ts`, with its own
 * escalating permission tiers.
 *
 * The request carries no `customerId` at all — ownership is derived
 * exclusively from the server-loaded order's own `customerId` compared
 * against `request.auth.uid`, never trusted from client input.
 *
 * Once confirmed, the customer can no longer self-cancel — a stable
 * `failed-precondition` domain error, not a generic failure, so the
 * Flutter client can render a specific "sipariş artık iptal edilemez"
 * message rather than a raw error string.
 *
 * **No loyalty write here, by design.** A successful `cancelled`
 * transition is picked up automatically by the already-built, unmodified
 * `onOrderTerminalFailureOrRefund.ts` trigger — writing `status:
 * "cancelled"` is all this callable ever needs to do to trigger Boncuk
 * redemption restoration.
 */
export const cancelTakeawayOrder = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    const uid = requireRealCustomer(request);
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireTakeawayOrderId(data.orderId);

    const db = getFirestore();
    const orderRef = db.collection("orders").doc(orderId);

    return db.runTransaction(async (tx) => {
      const orderSnap = await tx.get(orderRef);
      if (!orderSnap.exists) {
        throw new HttpsError("not-found", "Order not found.");
      }
      const order = orderSnap.data()!;

      if (order.customerId !== uid) {
        // Never confirms/denies the order's existence differently for a
        // non-owner vs. a genuinely missing order beyond this point — a
        // caller who isn't the owner gets the exact same permission-denied
        // outcome regardless of the order's real status.
        throw new HttpsError("permission-denied", "You do not own this order.");
      }
      if (order.channel !== "takeaway") {
        throw new HttpsError("failed-precondition", "This order is not a takeaway order.");
      }

      const currentStatus = order.status as string;

      if (currentStatus === "cancelled") {
        return { orderId, status: "cancelled", duplicate: true };
      }
      if (currentStatus !== "pendingConfirmation") {
        throw new HttpsError(
          "failed-precondition",
          "This order can no longer be cancelled by the customer — it has already been responded to.",
        );
      }
      if (!canTransition("pendingConfirmation", "cancelled")) {
        throw new HttpsError("failed-precondition", "Transition not allowed.");
      }

      const now = Timestamp.now();

      applyTakeawayLifecycleTransition({
        tx,
        orderRef,
        orderId,
        order,
        fromStatus: "pendingConfirmation",
        toStatus: "cancelled",
        actorType: "customer",
        now,
        terminalReasonCode: null,
      });
      writeTakeawayOrderStatusChangeAuditEvent({
        tx,
        db,
        orderId,
        organizationId: order.organizationId as string,
        branchId: order.branchId as string,
        fromStatus: "pendingConfirmation",
        toStatus: "cancelled",
        actorType: "customer",
        actorUid: uid,
        now,
      });

      return { orderId, status: "cancelled", duplicate: false };
    });
  },
);
