import { randomUUID } from "crypto";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import { applyOrderLifecycleTransition, writeOrderStatusChangeAuditEvent } from "./orderLifecycle";

/**
 * AP-6 Sprint 2 — manually dispatches a `delivery`-channel order to an
 * in-house/pool courier. Staff-only (`manageCourierDispatch`), mirrors
 * `advanceDeliveryOrderStatus.ts`'s exact auth/branch-derivation pattern:
 * the order is loaded first, `organizationId`/`branchId` derived from IT
 * (never client input), `requireStaffPermission` + `requireBranchAccess`
 * against those.
 *
 * **`MarketplaceCourierImmutableViolation`**: if the order already carries
 * `courierType: "marketplace"`, this callable refuses to touch it at all —
 * a marketplace-carried order is dispatched by the external platform, never
 * reassignable through our own manual flow. Stable `details.reason`
 * (`"courier/marketplace-immutable"`), mirrors `boncukRedemptionErrors.ts`'s
 * own `details.reason` convention so a client can branch on it without
 * parsing `message`. **No live path in this codebase can set
 * `courierType: "marketplace"` today** (no marketplace order-intake exists
 * yet, `docs/business_rules.md` BR-MKT-003) — this guard is forward
 * groundwork, verified in tests by directly seeding the field.
 *
 * Separately, this callable never hands out a `type: "marketplace"`
 * `Courier` itself — a marketplace courier is never manually dispatched
 * through our own roster.
 *
 * On success: generates an opaque `trackingToken` (`crypto.randomUUID()`,
 * the same mechanism `correlationId.ts` already uses), writes it plus
 * `assignedCourierId`/`courierType` onto the order, appends the order to
 * the courier's `activeOrderIds`, sets the courier `dispatchStatus:
 * "delivering"`, and — reusing `canTransition`/`applyOrderLifecycleTransition`/
 * `writeOrderStatusChangeAuditEvent` exactly as `advanceDeliveryOrderStatus.ts`
 * does — transitions `ready -> outForDelivery` (a no-op transition, courier
 * fields still updated, if the order is already `outForDelivery`).
 */

function requireString(value: unknown, field: string): string {
  if (typeof value !== "string" || value.length === 0) {
    throw new HttpsError("invalid-argument", `${field} is required.`);
  }
  return value;
}

export const assignCourierToOrder = onCall(
  { enforceAppCheck: shouldEnforceAppCheck() },
  async (request) => {
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "Sign-in is required.");
    }
    const data = (request.data ?? {}) as Record<string, unknown>;
    const orderId = requireString(data.orderId, "orderId");
    const courierId = requireString(data.courierId, "courierId");

    const db = getFirestore();
    const orderRef = db.collection("orders").doc(orderId);
    const courierRef = db.collection("couriers").doc(courierId);

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

      requireStaffPermission(request, organizationId, "manageCourierDispatch");
      requireBranchAccess(request, organizationId, branchId);

      if (order.courierType === "marketplace") {
        throw new HttpsError(
          "failed-precondition",
          "This order is being carried by a marketplace courier and cannot be manually reassigned.",
          { reason: "courier/marketplace-immutable" },
        );
      }

      const currentStatus = order.status as OrderStatus;
      const alreadyOutForDelivery = currentStatus === "outForDelivery";
      // AP-6 Sprint 3 — "readyForPickup" is the consortium-order analogue
      // of "ready" (our own kitchen never produced it, but it's equally
      // eligible for courier assignment) — both are valid sources for the
      // exact same outForDelivery target below.
      if (
        !alreadyOutForDelivery &&
        currentStatus !== "ready" &&
        currentStatus !== "readyForPickup"
      ) {
        throw new HttpsError(
          "failed-precondition",
          `Order is not eligible for courier assignment (current status: "${currentStatus}").`,
        );
      }
      if (!alreadyOutForDelivery && !canTransition(currentStatus, "outForDelivery")) {
        // Defensive only — the table already guarantees this today, but
        // this callable must never assume a transition it doesn't itself
        // verify.
        throw new HttpsError("failed-precondition", "Transition not allowed.");
      }

      const courierSnap = await tx.get(courierRef);
      if (!courierSnap.exists) {
        throw new HttpsError("not-found", "Courier not found.");
      }
      const courier = courierSnap.data()!;
      if (courier.branchId !== branchId) {
        throw new HttpsError(
          "failed-precondition",
          "This courier is not registered at the order's branch.",
        );
      }
      if (courier.type === "marketplace") {
        throw new HttpsError(
          "failed-precondition",
          "A marketplace-typed courier can never be manually assigned through this callable.",
        );
      }

      const now = Timestamp.now();
      const trackingToken = randomUUID();
      const activeOrderIds: string[] = Array.isArray(courier.activeOrderIds)
        ? courier.activeOrderIds
        : [];

      tx.set(
        orderRef,
        {
          assignedCourierId: courierId,
          courierType: courier.type ?? "internal",
          trackingToken,
        },
        { merge: true },
      );

      tx.set(
        courierRef,
        {
          activeOrderIds: activeOrderIds.includes(orderId)
            ? activeOrderIds
            : [...activeOrderIds, orderId],
          dispatchStatus: "delivering",
          updatedAt: now,
          revision: (Number(courier.revision) || 1) + 1,
        },
        { merge: true },
      );

      if (!alreadyOutForDelivery) {
        const actorUid = request.auth!.uid;
        const token = request.auth!.token as Record<string, unknown>;
        const rolesByOrg = token.roles as Record<string, unknown> | undefined;
        const actorRoles = Array.isArray(rolesByOrg?.[organizationId])
          ? (rolesByOrg![organizationId] as string[])
          : null;

        applyOrderLifecycleTransition({
          tx,
          orderRef,
          orderId,
          order,
          fromStatus: currentStatus,
          toStatus: "outForDelivery",
          actorType: "staff",
          now,
        });
        writeOrderStatusChangeAuditEvent({
          tx,
          db,
          orderId,
          organizationId,
          branchId,
          fromStatus: currentStatus,
          toStatus: "outForDelivery",
          actorType: "staff",
          actorUid,
          actorRoles,
          now,
        });
      }

      return {
        orderId,
        courierId,
        trackingToken,
        status: alreadyOutForDelivery ? currentStatus : "outForDelivery",
      };
    });
  },
);
