import { createHash } from "crypto";
import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, type DocumentData } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess, roleHasPermission, type StaffPermission } from "./staffAuthorization";
import { requireActiveDeviceSession } from "./trustedDevice";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId } from "./correlationId";
import { DELIVERY_PAYMENT_METHOD_CATALOG } from "./deliveryPaymentMethodCatalog";
import { CASH_SESSIONS_COLLECTION, CASH_MOVEMENTS_COLLECTION, type CashSessionDoc, type CashMovementDoc } from "./cashDomain";
import { applyDeliveryLifecycleTransition, writeDeliveryOrderStatusChangeAuditEvent } from "./deliveryOrderLifecycle";
import { STAFF_DELIVERY_PAYMENT_METHOD_IDS } from "./submitStaffDeliveryOrder";

/**
 * 2026-11-11 — Faz 2b: "Kurye Döndü — Hesap Kapat". When a courier comes back,
 * the cashier closes every order on them in ONE server call
 * ([settleCourierReturn]): each delivered order gets one `deliveryCollections`
 * record (the method the customer actually paid with — cash, POS or a
 * meal-card brand — which may differ from the one planned; both are audited),
 * the cash part enters the till's active cash session as a `courierCashIn`
 * movement (so the drawer's expected cash includes it), the orders are
 * completed, cancelled ones are dropped from the courier's list, and the
 * courier becomes available. Product-owner decisions:
 * - a cash difference (courier brings more/less than expected) can only be
 *   closed by a manager-tier user (`approveCashReconciliation`) with a
 *   mandatory reason — recorded as "Kurye Farkı";
 * - an undelivered order goes through the existing staff cancellation
 *   (`cancelDeliveryOrderForStaff`, reason required) BEFORE settling — it is
 *   never collected;
 * - every order on the courier closes in one go (no partial return);
 * - the collected amount is the order total (tips out of scope).
 * The Z report adds these collections to the matching tender lines and shows
 * "Paket Servis Tahsilatı" and "Kurye Farkı" (`cashRegisterEngine.ts`).
 */
export const DELIVERY_COLLECTIONS_COLLECTION = "deliveryCollections";
export const COURIER_SETTLEMENTS_COLLECTION = "courierSettlements";

const MAX_REASON_LENGTH = 300;
const MAX_SLIP_LENGTH = 64;

export type CollectionReportingCategory = "cash" | "card" | "mealCard";

export interface DeliveryCollectionDoc {
  organizationId: string;
  branchId: string;
  orderId: string;
  orderNumber: string;
  courierId: string;
  settlementId: string;
  cashSessionId: string;
  paymentMethodId: string;
  paymentMethodDisplayName: string;
  reportingCategory: CollectionReportingCategory;
  plannedPaymentMethodId: string | null;
  amountMinorUnits: number;
  currencyCode: string;
  slipNumber: string | null;
  collectedAt: Timestamp;
  collectedByStaffUid: string;
}

export interface CourierSettlementDoc {
  organizationId: string;
  branchId: string;
  courierId: string;
  courierName: string;
  cashSessionId: string;
  orderIds: string[];
  cancelledOrderIds: string[];
  expectedCashMinorUnits: number;
  receivedCashMinorUnits: number;
  /** received − expected: negative = the courier brought less ("açık"). */
  differenceMinorUnits: number;
  differenceReason: string | null;
  totalCollectedMinorUnits: number;
  currencyCode: string;
  createdAt: Timestamp;
  createdByStaffUid: string;
}

/** What the courier owes for one order: its total, minus any Boncuk already redeemed. */
export function orderAmountDueMinorUnits(order: DocumentData): number {
  const remaining = order.boncukRedemption?.remainingPayableMinorUnits;
  if (typeof remaining === "number") return remaining;
  return Number(order.pricing?.grandTotal?.minorUnits ?? 0);
}

export function reportingCategoryFor(paymentMethodId: string): CollectionReportingCategory | null {
  const category = DELIVERY_PAYMENT_METHOD_CATALOG[paymentMethodId]?.reportingCategory;
  return category === "cash" || category === "card" || category === "mealCard" ? category : null;
}

export interface SettlementLineInput {
  orderId: string;
  amountDueMinorUnits: number;
  paymentMethodId: string;
}

/**
 * Pure: the cash the courier should bring (the cash-paid orders), the
 * difference to what they brought, and the totals per method.
 */
export function computeCourierSettlement(lines: SettlementLineInput[], receivedCashMinorUnits: number) {
  let expectedCashMinorUnits = 0;
  let totalCollectedMinorUnits = 0;
  const totalsByPaymentMethod: Record<string, number> = {};
  for (const line of lines) {
    totalCollectedMinorUnits += line.amountDueMinorUnits;
    totalsByPaymentMethod[line.paymentMethodId] = (totalsByPaymentMethod[line.paymentMethodId] ?? 0) + line.amountDueMinorUnits;
    if (reportingCategoryFor(line.paymentMethodId) === "cash") expectedCashMinorUnits += line.amountDueMinorUnits;
  }
  return {
    expectedCashMinorUnits,
    receivedCashMinorUnits,
    differenceMinorUnits: receivedCashMinorUnits - expectedCashMinorUnits,
    totalCollectedMinorUnits,
    totalsByPaymentMethod,
  };
}

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) invalid(`${field} is required.`);
  return (raw as string).trim();
}

function actorHasPermission(request: CallableRequest, organizationId: string, permission: StaffPermission): boolean {
  const token = request.auth?.token;
  const organizationAccess = token?.organizationAccess;
  if (!Array.isArray(organizationAccess) || !organizationAccess.includes(organizationId)) return false;
  const rolesForOrg = (token?.roles as Record<string, unknown> | undefined)?.[organizationId];
  return Array.isArray(rolesForOrg) && rolesForOrg.some((role) => typeof role === "string" && roleHasPermission(role, permission));
}

async function authorize(request: CallableRequest, data: Record<string, unknown>) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const organizationId = requireString(data.organizationId, "organizationId");
  const branchId = requireString(data.branchId, "branchId");
  const deviceId = requireString(data.deviceId, "deviceId");
  const deviceSessionId = requireString(data.deviceSessionId, "deviceSessionId");
  await requireStaffPermission(request, organizationId, "manageDeliveryOrders");
  await requireStaffPermission(request, organizationId, "manageCashSessions");
  await requireBranchAccess(request, organizationId, branchId);
  await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);
  return { organizationId, branchId, uid: request.auth.uid };
}

function courierServesBranch(courier: DocumentData, branchId: string): boolean {
  const eligible = Array.isArray(courier.eligibleBranchIds) ? (courier.eligibleBranchIds as string[]) : [];
  return courier.branchId === branchId || courier.primaryBranchId === branchId || eligible.includes(branchId);
}

/**
 * The orders a returning courier has to close, with the amount due and the
 * planned pay-on-delivery method — server-computed, so the screen never
 * guesses an expected amount.
 */
export const getCourierSettlementPreview = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const { organizationId, branchId } = await authorize(request, data);
  const courierId = requireString(data.courierId, "courierId");
  const db = getFirestore();
  const courierSnap = await db.collection("couriers").doc(courierId).get();
  if (!courierSnap.exists || !courierServesBranch(courierSnap.data()!, branchId)) {
    throw new HttpsError("not-found", "Courier not found for this branch.");
  }
  const courier = courierSnap.data()!;
  const activeOrderIds: string[] = Array.isArray(courier.activeOrderIds) ? courier.activeOrderIds : [];
  const orders = [];
  for (const orderId of activeOrderIds) {
    const snap = await db.collection("orders").doc(orderId).get();
    if (!snap.exists) continue;
    const order = snap.data()!;
    if (order.organizationId !== organizationId || order.branchId !== branchId) continue;
    orders.push({
      orderId,
      orderNumber: order.orderNumber as string,
      status: order.status as string,
      customerName: [order.contactFirstName, order.contactLastName].filter((p) => typeof p === "string" && p.length > 0).join(" "),
      addressSummary: [order.deliveryAddressSnapshot?.neighborhoodName, order.deliveryAddressSnapshot?.streetName]
        .filter((p) => typeof p === "string" && p.length > 0).join(", "),
      amountDueMinorUnits: orderAmountDueMinorUnits(order),
      plannedPaymentMethodId: (order.paymentMethodSnapshot?.paymentMethodId as string | undefined) ?? null,
    });
  }
  return { courierId, courierName: (courier.displayName as string | undefined) ?? courierId, orders };
});

export const settleCourierReturn = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const { organizationId, branchId, uid } = await authorize(request, data);
  const courierId = requireString(data.courierId, "courierId");
  const cashSessionId = requireString(data.cashSessionId, "cashSessionId");
  const settlementKey = requireString(data.settlementKey, "settlementKey");
  if (settlementKey.length > 128) invalid("settlementKey is too long.");
  const received = data.receivedCashMinorUnits;
  if (typeof received !== "number" || !Number.isInteger(received) || received < 0) {
    invalid("receivedCashMinorUnits must be a non-negative integer.");
  }
  const receivedCashMinorUnits = received as number;
  const rawReason = typeof data.differenceReason === "string" ? data.differenceReason.trim() : "";
  if (rawReason.length > MAX_REASON_LENGTH) invalid(`differenceReason must be at most ${MAX_REASON_LENGTH} characters.`);
  const rawDeliveries = Array.isArray(data.deliveries) ? (data.deliveries as Array<Record<string, unknown>>) : [];
  const deliveries = rawDeliveries.map((d) => {
    const orderId = requireString(d.orderId, "deliveries[].orderId");
    const paymentMethodId = requireString(d.paymentMethodId, "deliveries[].paymentMethodId");
    if (!STAFF_DELIVERY_PAYMENT_METHOD_IDS.has(paymentMethodId)) invalid(`deliveries[].paymentMethodId "${paymentMethodId}" is not a pay-on-delivery method.`);
    const slip = typeof d.slipNumber === "string" ? d.slipNumber.trim() : "";
    if (slip.length > MAX_SLIP_LENGTH) invalid("deliveries[].slipNumber is too long.");
    return { orderId, paymentMethodId, slipNumber: slip.length > 0 ? slip : null };
  });
  if (new Set(deliveries.map((d) => d.orderId)).size !== deliveries.length) invalid("deliveries contains the same order twice.");
  const isManager = actorHasPermission(request, organizationId, "approveCashReconciliation");

  const db = getFirestore();
  const settlementId = `cs-${createHash("sha256").update(`${uid}|${settlementKey}`).digest("hex").slice(0, 40)}`;
  const settlementRef = db.collection(COURIER_SETTLEMENTS_COLLECTION).doc(settlementId);

  return db.runTransaction(async (tx) => {
    // --- read phase ----------------------------------------------------
    const existing = await tx.get(settlementRef);
    if (existing.exists) {
      const doc = existing.data() as CourierSettlementDoc;
      return { settlementId, duplicate: true, differenceMinorUnits: doc.differenceMinorUnits, totalCollectedMinorUnits: doc.totalCollectedMinorUnits };
    }
    const courierRef = db.collection("couriers").doc(courierId);
    const courierSnap = await tx.get(courierRef);
    if (!courierSnap.exists || !courierServesBranch(courierSnap.data()!, branchId)) {
      throw new HttpsError("not-found", "Courier not found for this branch.");
    }
    const courier = courierSnap.data()!;
    const cashSessionRef = db.collection(CASH_SESSIONS_COLLECTION).doc(cashSessionId);
    const cashSessionSnap = await tx.get(cashSessionRef);
    if (!cashSessionSnap.exists) throw new HttpsError("not-found", "Cash session not found.");
    const cashSession = cashSessionSnap.data() as CashSessionDoc;
    if (cashSession.organizationId !== organizationId || cashSession.branchId !== branchId) {
      throw new HttpsError("not-found", "Cash session not found.");
    }
    if (cashSession.status !== "active") {
      throw new HttpsError("failed-precondition", "The cash session must be active.", { code: "courierSettlement/cash-session-not-active" });
    }
    if (cashSession.cashRegisterModel === "cashierBound" && cashSession.openedByStaffUid !== uid) {
      throw new HttpsError("permission-denied", "This drawer is cashier-bound to the staff member who opened it.");
    }

    const activeOrderIds: string[] = Array.isArray(courier.activeOrderIds) ? courier.activeOrderIds : [];
    const orderRefs = activeOrderIds.map((id) => db.collection("orders").doc(id));
    const orderSnaps = await Promise.all(orderRefs.map((ref) => tx.get(ref)));
    const collectionRefs = deliveries.map((d) => db.collection(DELIVERY_COLLECTIONS_COLLECTION).doc(d.orderId));
    const collectionSnaps = await Promise.all(collectionRefs.map((ref) => tx.get(ref)));

    const deliveryByOrderId = new Map(deliveries.map((d) => [d.orderId, d]));
    const open: Array<{ ref: FirebaseFirestore.DocumentReference; id: string; order: DocumentData }> = [];
    const cancelledOrderIds: string[] = [];
    orderSnaps.forEach((snap, i) => {
      if (!snap.exists) {
        cancelledOrderIds.push(activeOrderIds[i]);
        return;
      }
      const order = snap.data()!;
      if (order.status === "cancelled" || order.status === "completed" || order.status === "rejected") {
        cancelledOrderIds.push(activeOrderIds[i]);
        return;
      }
      open.push({ ref: orderRefs[i], id: activeOrderIds[i], order });
    });
    // Product-owner decision 4: everything on the courier closes in one go.
    const missing = open.filter((o) => !deliveryByOrderId.has(o.id)).map((o) => o.id);
    const unknown = deliveries.filter((d) => !open.some((o) => o.id === d.orderId)).map((d) => d.orderId);
    if (missing.length > 0 || unknown.length > 0) {
      throw new HttpsError("failed-precondition", "Every open order on the courier must be settled at once (and only those).", {
        code: "courierSettlement/orders-mismatch", missing, unknown,
      });
    }
    collectionSnaps.forEach((snap, i) => {
      if (snap.exists) {
        throw new HttpsError("failed-precondition", `Order ${deliveries[i].orderId} is already collected.`, { code: "courierSettlement/already-collected" });
      }
    });
    for (const o of open) {
      if (o.order.organizationId !== organizationId || o.order.branchId !== branchId || o.order.channel !== "delivery") {
        throw new HttpsError("failed-precondition", `Order ${o.id} is not a delivery order of this branch.`);
      }
      if (o.order.status !== "outForDelivery") {
        throw new HttpsError("failed-precondition", `Order ${o.id} is not out for delivery (status: "${o.order.status}").`, { code: "courierSettlement/not-out-for-delivery" });
      }
    }

    const lines = open.map((o) => ({
      orderId: o.id,
      amountDueMinorUnits: orderAmountDueMinorUnits(o.order),
      paymentMethodId: deliveryByOrderId.get(o.id)!.paymentMethodId,
    }));
    const totals = computeCourierSettlement(lines, receivedCashMinorUnits);
    if (totals.differenceMinorUnits !== 0) {
      if (!isManager) {
        throw new HttpsError("permission-denied", "A cash difference can only be closed by a manager.", { code: "courierSettlement/difference-needs-manager" });
      }
      if (rawReason.length === 0) invalid("differenceReason is required when the cash differs.");
    }

    // --- write phase ---------------------------------------------------
    const now = Timestamp.now();
    const currencyCode = cashSession.currencyCode ?? "TRY";
    const actorRoles = Array.isArray((request.auth!.token.roles as Record<string, unknown> | undefined)?.[organizationId])
      ? ((request.auth!.token.roles as Record<string, unknown>)[organizationId] as string[])
      : null;
    open.forEach((o, i) => {
      const delivery = deliveryByOrderId.get(o.id)!;
      const plannedPaymentMethodId = (o.order.paymentMethodSnapshot?.paymentMethodId as string | undefined) ?? null;
      const method = DELIVERY_PAYMENT_METHOD_CATALOG[delivery.paymentMethodId];
      const collection: DeliveryCollectionDoc = {
        organizationId, branchId, orderId: o.id, orderNumber: String(o.order.orderNumber ?? o.id),
        courierId, settlementId, cashSessionId,
        paymentMethodId: delivery.paymentMethodId,
        paymentMethodDisplayName: method.displayName,
        reportingCategory: reportingCategoryFor(delivery.paymentMethodId)!,
        plannedPaymentMethodId,
        amountMinorUnits: lines[i].amountDueMinorUnits,
        currencyCode,
        slipNumber: delivery.slipNumber,
        collectedAt: now,
        collectedByStaffUid: uid,
      };
      tx.set(db.collection(DELIVERY_COLLECTIONS_COLLECTION).doc(o.id), collection);
      // Product-owner decision 2: the old and the new method are audited.
      if (plannedPaymentMethodId !== delivery.paymentMethodId) {
        writeAuditEvent({
          tx, db, eventId: `deliveryCollection-${o.id}-methodChanged`, organizationId, branchId,
          type: "deliveryCollection.paymentMethodChanged", targetRef: o.ref.path,
          previousValue: { paymentMethodId: plannedPaymentMethodId },
          newValue: { paymentMethodId: delivery.paymentMethodId },
          actorType: "staff", actorUid: uid, actorRoles, correlationId: generateCorrelationId(), now,
        });
      }
      applyDeliveryLifecycleTransition({
        tx, orderRef: o.ref, orderId: o.id, order: o.order,
        fromStatus: "outForDelivery", toStatus: "completed", actorType: "staff", now,
      });
      writeDeliveryOrderStatusChangeAuditEvent({
        tx, db, orderId: o.id, organizationId, branchId,
        fromStatus: "outForDelivery", toStatus: "completed",
        actorType: "staff", actorUid: uid, actorRoles, reasonCode: null, reasonMessage: null, now,
      });
    });

    if (receivedCashMinorUnits > 0) {
      const movement: CashMovementDoc = {
        organizationId, branchId, sessionId: cashSessionId, drawerId: cashSession.drawerId,
        type: "courierCashIn", amountMinorUnits: receivedCashMinorUnits, currencyCode,
        reason: `Kurye tahsilatı (${(courier.displayName as string | undefined) ?? courierId})`,
        actorStaffUid: uid, timestamp: now, reversalOfMovementId: null, paymentAttemptId: null, refundRequestId: null,
      };
      tx.set(db.collection(CASH_MOVEMENTS_COLLECTION).doc(`courier-${settlementId}`), movement);
      tx.update(cashSessionRef, {
        settledAmountMinorUnits: cashSession.settledAmountMinorUnits + receivedCashMinorUnits,
        updatedAt: now,
        version: cashSession.version + 1,
      });
    }

    tx.set(courierRef, {
      activeOrderIds: [],
      dispatchStatus: "available",
      returnedAt: now,
      updatedAt: now,
      revision: (Number(courier.revision) || 1) + 1,
    }, { merge: true });

    const settlement: CourierSettlementDoc = {
      organizationId, branchId, courierId,
      courierName: (courier.displayName as string | undefined) ?? courierId,
      cashSessionId,
      orderIds: open.map((o) => o.id),
      cancelledOrderIds,
      expectedCashMinorUnits: totals.expectedCashMinorUnits,
      receivedCashMinorUnits,
      differenceMinorUnits: totals.differenceMinorUnits,
      differenceReason: totals.differenceMinorUnits !== 0 ? rawReason : null,
      totalCollectedMinorUnits: totals.totalCollectedMinorUnits,
      currencyCode,
      createdAt: now,
      createdByStaffUid: uid,
    };
    tx.set(settlementRef, settlement);
    writeAuditEvent({
      tx, db, eventId: `courierSettlement-${settlementId}`, organizationId, branchId,
      type: "courierSettlement.closed", targetRef: settlementRef.path,
      newValue: {
        courierId, orderIds: settlement.orderIds, expectedCashMinorUnits: totals.expectedCashMinorUnits,
        receivedCashMinorUnits, differenceMinorUnits: totals.differenceMinorUnits, totalsByPaymentMethod: totals.totalsByPaymentMethod,
      },
      reasonMessage: settlement.differenceReason,
      actorType: "staff", actorUid: uid, actorRoles, correlationId: generateCorrelationId(), now,
    });

    return {
      settlementId,
      duplicate: false,
      expectedCashMinorUnits: totals.expectedCashMinorUnits,
      differenceMinorUnits: totals.differenceMinorUnits,
      totalCollectedMinorUnits: totals.totalCollectedMinorUnits,
    };
  });
});
