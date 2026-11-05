import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { canTransition } from "./orderStatus";
import {
  requireDineInOrderId,
  applyDineInLifecycleTransition,
  writeDineInOrderStatusChangeAuditEvent,
} from "./dineInOrderLifecycle";

/**
 * `cancelMyPendingDineInOrder` — Self-Order QR Faz 4 (23-rule plan §4,
 * "müşteri kendi siparişini mutfak/kasa onayına kadar iptal edebilir").
 *
 * The first real, server-authoritative dine-in order cancellation of any
 * kind — `order_detail_screen.dart`'s existing "Siparişi İptal Et" button
 * only ever called the local, in-memory `ordersProvider.notifier
 * .cancelOrder` for every channel including this one; this callable is
 * what that UI is wired to for a `dineInQr` order specifically from this
 * phase on.
 *
 * Mirrors `cancelTakeawayOrder.ts`'s own customer-self-cancel shape and
 * reasoning closely, with one deliberate difference: **no
 * `requireRealCustomer` gate.** A dine-in table guest is very often
 * anonymous (never phone-verified) — `requireRealCustomer` would wrongly
 * lock an anonymous guest out of cancelling their own order, which this
 * rule explicitly grants to any guest regardless of identity type.
 * Ownership is instead proven by `order.guestAuthUid === request.auth
 * .uid` — a field `submitDineInOrder.ts` stamps for BOTH identity types
 * (`buildDineInOrderDocument`'s `guestAuthUid: params.guestAuthUid`),
 * unlike `customerId`, which stays `null` for an anonymous guest and so
 * can never be the ownership check here.
 *
 * `pendingConfirmation` only — the exact "until kitchen/kasa onayına
 * kadar" boundary: once staff responds (line approval moves the order to
 * `confirmed`) or rejects/cancels it any other way, this callable's own
 * precondition check closes the window, mirroring `cancelTakeawayOrder
 * .ts`'s identical `pendingConfirmation`-only gate. No reason code is
 * collected, exactly like that same precedent (`terminalReasonCode:
 * null`) — a customer self-cancel is not an operational incident needing
 * a staff-facing reason taxonomy.
 */
export const cancelMyPendingDineInOrder = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const uid = request.auth.uid;
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireDineInOrderId(data.orderId);

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
      if (order.guestAuthUid !== uid) {
        // Never confirms/denies the order's existence differently for a
        // non-owner vs. a genuinely missing order beyond this point —
        // mirrors `cancelTakeawayOrder.ts`'s own identical reasoning.
        throw new HttpsError("permission-denied", "You do not own this order.");
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
      const organizationId = order.organizationId as string;
      const branchId = order.branchId as string;

      applyDineInLifecycleTransition({
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
      writeDineInOrderStatusChangeAuditEvent({
        tx,
        db,
        orderId,
        organizationId,
        branchId,
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
