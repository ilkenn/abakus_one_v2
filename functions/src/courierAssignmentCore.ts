import { randomUUID } from "crypto";
import type { CallableRequest } from "firebase-functions/v2/https";
import type { DocumentData, DocumentReference, Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import type { OrderStatus } from "./orderStatus";
import { applyOrderLifecycleTransition, writeOrderStatusChangeAuditEvent } from "./orderLifecycle";

/**
 * 2026-11-12 (Faz 3a) — the write half of assigning a courier to a delivery
 * order, shared by `assignCourierToOrder` (direct assignment by staff) and
 * `respondToCourierPoolRequest` (approving an external courier's pool
 * request). Pure writes: every read (order, courier, previous courier) is
 * done by the caller first, because a Firestore transaction must finish all
 * of its reads before its first write.
 *
 * Behaviour is exactly the pre-existing `assignCourierToOrder` one —
 * `assignedCourierId`/`courierType`/`trackingToken` on the order, the order
 * appended to the courier's `activeOrderIds` + `delivering`, and the
 * `ready`/`readyForPickup -> outForDelivery` transition with its audit
 * event — plus one fix: on a **re**assignment to a different courier the
 * order is removed from the previous courier's `activeOrderIds` (before,
 * it stayed there, so the previous courier's "Kurye Hesap Kapat" would
 * have demanded an order someone else carried).
 */

/**
 * A `pool` (external) courier is not bound to one branch — it serves every
 * branch of its organization inside its `serviceDistrictIds`. Every other
 * courier must be registered at the order's branch (unchanged rule).
 */
export function courierCanServeOrder(courier: DocumentData, organizationId: string, branchId: string): boolean {
  if (courier.type === "pool") {
    return courier.organizationId === organizationId && (courier.status ?? "active") === "active";
  }
  return courier.branchId === branchId;
}

export interface ApplyCourierAssignmentParams {
  tx: Transaction;
  db: Firestore;
  request: CallableRequest;
  orderRef: DocumentReference;
  orderId: string;
  order: DocumentData;
  organizationId: string;
  branchId: string;
  courierRef: DocumentReference;
  courierId: string;
  courier: DocumentData;
  /** The order's current courier when it is being moved to [courierId]. */
  previousCourier?: { ref: DocumentReference; data: DocumentData } | null;
  now: Timestamp;
}

export function applyCourierAssignment(p: ApplyCourierAssignmentParams): { trackingToken: string; status: OrderStatus } {
  const currentStatus = p.order.status as OrderStatus;
  const alreadyOutForDelivery = currentStatus === "outForDelivery";
  const trackingToken = randomUUID();
  const activeOrderIds: string[] = Array.isArray(p.courier.activeOrderIds) ? p.courier.activeOrderIds : [];

  p.tx.set(
    p.orderRef,
    {
      assignedCourierId: p.courierId,
      courierType: p.courier.type ?? "internal",
      trackingToken,
    },
    { merge: true },
  );

  p.tx.set(
    p.courierRef,
    {
      activeOrderIds: activeOrderIds.includes(p.orderId) ? activeOrderIds : [...activeOrderIds, p.orderId],
      dispatchStatus: "delivering",
      updatedAt: p.now,
      revision: (Number(p.courier.revision) || 1) + 1,
    },
    { merge: true },
  );

  if (p.previousCourier) {
    const previousIds: string[] = Array.isArray(p.previousCourier.data.activeOrderIds)
      ? p.previousCourier.data.activeOrderIds
      : [];
    const remaining = previousIds.filter((id) => id !== p.orderId);
    p.tx.set(
      p.previousCourier.ref,
      {
        activeOrderIds: remaining,
        ...(remaining.length === 0 ? { dispatchStatus: "available" } : {}),
        updatedAt: p.now,
        revision: (Number(p.previousCourier.data.revision) || 1) + 1,
      },
      { merge: true },
    );
  }

  if (!alreadyOutForDelivery) {
    const actorUid = p.request.auth!.uid;
    const token = p.request.auth!.token as Record<string, unknown>;
    const rolesByOrg = token.roles as Record<string, unknown> | undefined;
    const actorRoles = Array.isArray(rolesByOrg?.[p.organizationId])
      ? (rolesByOrg![p.organizationId] as string[])
      : null;

    applyOrderLifecycleTransition({
      tx: p.tx,
      orderRef: p.orderRef,
      orderId: p.orderId,
      order: p.order,
      fromStatus: currentStatus,
      toStatus: "outForDelivery",
      actorType: "staff",
      now: p.now,
    });
    writeOrderStatusChangeAuditEvent({
      tx: p.tx,
      db: p.db,
      orderId: p.orderId,
      organizationId: p.organizationId,
      branchId: p.branchId,
      fromStatus: currentStatus,
      toStatus: "outForDelivery",
      actorType: "staff",
      actorUid,
      actorRoles,
      now: p.now,
    });
  }

  return { trackingToken, status: alreadyOutForDelivery ? currentStatus : "outForDelivery" };
}
