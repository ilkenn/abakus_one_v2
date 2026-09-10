import { randomUUID } from "crypto";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, type DocumentSnapshot } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import { applyOrderLifecycleTransition, writeOrderStatusChangeAuditEvent } from "./orderLifecycle";

/**
 * AP-6 Sprint 3 — multi-pickup/multi-drop batch dispatch: assigns several
 * orders to the SAME courier in one call, for the cashier's "N Paket
 * Seçildi — Tek Kuryeye Ata" dispatch-console action (neighborhood-clustered
 * or pickup-clustered orders headed out together). Reuses
 * `assignCourierToOrder.ts`'s exact per-order guard sequence (channel,
 * marketplace-immutability, status-eligibility, courier-branch-match,
 * courier-not-marketplace), looped, under the SAME `manageCourierDispatch`
 * permission (the same class of dispatch decision, not a new one).
 *
 * **Fails the whole batch closed on any single invalid order** — no
 * partial-batch success; a cashier who selects one already-assigned or
 * marketplace-carried order among several valid ones gets one clear error
 * and zero writes, never a partially-applied batch to untangle.
 *
 * **Pickup/drop sequencing**: `Courier.activeOrderIds`'s own append order IS
 * the route sequence — this callable appends `orderIds` in the exact order
 * the caller supplied them (which the dispatch console populates in the
 * cashier's own selection order), in a single accumulated write to the
 * courier document. Deliberately no separate sequencing field and no route
 * optimization — not requested, and Firestore transactions only permit one
 * net write per document path, so N separate `tx.set` calls against the
 * same courier ref within one transaction would be a real bug, not a
 * style choice (see this file's own write phase below).
 */

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value;
}

function requireOrderIds(value: unknown): string[] {
  if (!Array.isArray(value) || value.length === 0) {
    throw new HttpsError("invalid-argument", "orderIds must be a non-empty array.");
  }
  const ids = value.map((v, i) => requireString(v, `orderIds[${i}]`));
  const unique = new Set(ids);
  if (unique.size !== ids.length) {
    throw new HttpsError("invalid-argument", "orderIds must not contain duplicates.");
  }
  return ids;
}

export const batchAssignCourierToOrders = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderIds = requireOrderIds(data.orderIds);
    const courierId = requireString(data.courierId, "courierId");

    const db = getFirestore();
    const orderRefs = orderIds.map((id) => db.collection("orders").doc(id));
    const courierRef = db.collection("couriers").doc(courierId);

    return db.runTransaction(async (tx) => {
      // Read phase — every tx.get() below happens before any tx.set() in
      // the write phase further down (Firestore's own read-before-write
      // transaction rule, the same discipline `assignCourierToOrder.ts`/
      // `acceptOrderLine.ts` already follow).
      const orderSnaps: DocumentSnapshot[] = [];
      for (const orderRef of orderRefs) {
        orderSnaps.push(await tx.get(orderRef));
      }
      const courierSnap = await tx.get(courierRef);

      if (!courierSnap.exists) {
        throw new HttpsError("not-found", "Courier not found.");
      }
      const courier = courierSnap.data()!;
      const organizationId = courier.organizationId as string;
      const branchId = courier.branchId as string;

      // Auth checked immediately after loading the one document
      // (`couriers/{courierId}`) that determines this call's org/branch
      // scope — same "derive scope from a server-loaded doc, check
      // permission before any further business-rule inspection" ordering
      // `assignCourierToOrder.ts` follows, so an authenticated-but-
      // unauthorized-for-this-org caller learns nothing about the orders'
      // existence/state before being rejected.
      requireStaffPermission(request, organizationId, "manageCourierDispatch");
      requireBranchAccess(request, organizationId, branchId);

      if (courier.type === "marketplace") {
        throw new HttpsError(
          "failed-precondition",
          "A marketplace-typed courier can never be manually assigned through this callable.",
        );
      }

      const perOrder: {
        orderRef: FirebaseFirestore.DocumentReference;
        orderId: string;
        order: FirebaseFirestore.DocumentData;
        currentStatus: OrderStatus;
        alreadyOutForDelivery: boolean;
      }[] = [];

      for (let i = 0; i < orderRefs.length; i++) {
        const orderSnap = orderSnaps[i];
        const orderId = orderIds[i];
        if (!orderSnap.exists) {
          throw new HttpsError("not-found", `Order not found: ${orderId}.`);
        }
        const order = orderSnap.data()!;

        if (order.channel !== "delivery") {
          throw new HttpsError(
            "failed-precondition",
            `Order ${orderId} is not a delivery order.`,
          );
        }
        if (order.organizationId !== organizationId) {
          throw new HttpsError(
            "failed-precondition",
            `Order ${orderId} does not belong to the courier's own organization.`,
          );
        }
        if (order.branchId !== branchId) {
          throw new HttpsError(
            "failed-precondition",
            `Order ${orderId} does not belong to the courier's own branch.`,
          );
        }
        if (order.courierType === "marketplace") {
          throw new HttpsError(
            "failed-precondition",
            `Order ${orderId} is being carried by a marketplace courier and cannot be manually reassigned.`,
            { reason: "courier/marketplace-immutable" },
          );
        }

        const currentStatus = order.status as OrderStatus;
        const alreadyOutForDelivery = currentStatus === "outForDelivery";
        if (
          !alreadyOutForDelivery &&
          currentStatus !== "ready" &&
          currentStatus !== "readyForPickup"
        ) {
          throw new HttpsError(
            "failed-precondition",
            `Order ${orderId} is not eligible for courier assignment (current status: "${currentStatus}").`,
          );
        }
        if (!alreadyOutForDelivery && !canTransition(currentStatus, "outForDelivery")) {
          throw new HttpsError("failed-precondition", `Transition not allowed for order ${orderId}.`);
        }

        perOrder.push({ orderRef: orderRefs[i], orderId, order, currentStatus, alreadyOutForDelivery });
      }

      // Write phase — no more reads below.
      const now = Timestamp.now();
      const actorUid = request.auth!.uid;
      const token = request.auth!.token as Record<string, unknown>;
      const rolesByOrg = token.roles as Record<string, unknown> | undefined;
      const actorRoles = Array.isArray(rolesByOrg?.[organizationId])
        ? (rolesByOrg![organizationId] as string[])
        : null;

      const results: { orderId: string; trackingToken: string; status: OrderStatus }[] = [];
      const existingActiveOrderIds: string[] = Array.isArray(courier.activeOrderIds)
        ? courier.activeOrderIds
        : [];
      const accumulatedActiveOrderIds = [...existingActiveOrderIds];

      for (const entry of perOrder) {
        const trackingToken = randomUUID();
        tx.set(
          entry.orderRef,
          {
            assignedCourierId: courierId,
            courierType: courier.type ?? "internal",
            trackingToken,
          },
          { merge: true },
        );

        if (!accumulatedActiveOrderIds.includes(entry.orderId)) {
          accumulatedActiveOrderIds.push(entry.orderId);
        }

        if (!entry.alreadyOutForDelivery) {
          applyOrderLifecycleTransition({
            tx,
            orderRef: entry.orderRef,
            orderId: entry.orderId,
            order: entry.order,
            fromStatus: entry.currentStatus,
            toStatus: "outForDelivery",
            actorType: "staff",
            now,
          });
          writeOrderStatusChangeAuditEvent({
            tx,
            db,
            orderId: entry.orderId,
            organizationId,
            branchId,
            fromStatus: entry.currentStatus,
            toStatus: "outForDelivery",
            actorType: "staff",
            actorUid,
            actorRoles,
            now,
          });
        }

        results.push({
          orderId: entry.orderId,
          trackingToken,
          status: entry.alreadyOutForDelivery ? entry.currentStatus : "outForDelivery",
        });
      }

      // Exactly one accumulated write to the courier document — never one
      // per order, which would silently drop all but the last write to the
      // same path within a single Firestore transaction.
      tx.set(
        courierRef,
        {
          activeOrderIds: accumulatedActiveOrderIds,
          dispatchStatus: "delivering",
          updatedAt: now,
          revision: (Number(courier.revision) || 1) + 1,
        },
        { merge: true },
      );

      return { courierId, results };
    });
  },
);
