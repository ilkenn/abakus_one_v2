import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { onDocumentUpdated } from "firebase-functions/v2/firestore";
import { getFirestore, Timestamp, type DocumentData, type DocumentReference, type Firestore, type Transaction } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId } from "./correlationId";
import { canTransition, type OrderStatus } from "./orderStatus";
import { DELIVERY_SERVICE_AREAS_COLLECTION, slugifyAddressComponent } from "./deliveryServiceAreas";
import { applyCourierAssignment, courierCanServeOrder } from "./courierAssignmentCore";
import { orderAmountDueMinorUnits } from "./courierSettlement";
import { STAFF_DELIVERY_PAYMENT_METHOD_IDS } from "./submitStaffDeliveryOrder";

/**
 * 2026-11-12 (Faz 3a) — the external-courier delivery pool.
 *
 * - **Restaurant couriers** (`couriers.type == "internal"`) never see the
 *   pool; they only get direct assignment by staff (unchanged).
 * - **External couriers** (`type == "pool"`, registered by a manager or
 *   above via `setCourier`) see a package only after staff publish it with
 *   "Havuza Gönder" (`publishOrderToPool`). Visibility is by region, not by
 *   branch: a listing carries the order's district (`districtId`, a
 *   `slugifyAddressComponent` slug) and an external courier sees every open
 *   listing of its organization inside its `serviceDistrictIds`.
 * - A listing never holds the customer's phone or name — only the
 *   neighborhood, the open address and the amount.
 * - An external courier can only "Talep Oluştur" (`requestPoolOrder`);
 *   several may request the same package. Staff holding
 *   `approveCourierPoolRequests` approve one
 *   (`respondToCourierPoolRequest`), which assigns the package to that
 *   courier and rejects every other pending request in the same
 *   transaction. No capacity limit applies to external couriers.
 * - Approving while the order is still being prepared *reserves* it for
 *   the courier (`poolReservedCourierId` + the planned courier); the real
 *   assignment (`-> outForDelivery`) is then the usual one-tap "Ata" once
 *   it is ready. Approving a ready order assigns it immediately.
 * - The courier marks "Yola Çıktım" (`courierMarkDeparted` — only records
 *   `departedAt`; the status already went to `outForDelivery` at
 *   assignment) and "Teslim Ettim" (`courierReportDelivered`, with the
 *   method the customer really paid). The order stays `outForDelivery`
 *   ("Teslim Edildi — Mutabakat Bekliyor") until the POS "Kurye Hesap
 *   Kapat" settlement completes it; the courier's copy of the customer
 *   phone is removed at delivery (KVKK).
 *
 * The courier's own read model is `courierAssignedOrders/{orderId}` (one
 * doc per order, readable only by the courier's own auth account), kept in
 * sync from the order by [onDeliveryOrderCourierProjection].
 */

export const DELIVERY_POOL_LISTINGS_COLLECTION = "deliveryPoolListings";
export const COURIER_POOL_REQUESTS_COLLECTION = "courierPoolRequests";
export const COURIER_ASSIGNED_ORDERS_COLLECTION = "courierAssignedOrders";
export const COURIER_ACCOUNTS_COLLECTION = "courierAccounts";

/** Order statuses in which a delivery order may be published to the pool. */
const PUBLISHABLE_STATUSES: ReadonlySet<string> = new Set(["confirmed", "preparing", "ready", "readyForPickup"]);
/** Order statuses after which nothing courier-side is open any more. */
const CLOSED_STATUSES: ReadonlySet<string> = new Set(["completed", "cancelled", "rejected", "refunded", "served"]);

export type PoolListingStatus = "open" | "assigned" | "withdrawn" | "closed";
export type PoolRequestStatus = "pending" | "approved" | "rejected";
export type PoolRequestRejection = "rejected" | "otherApproved" | "withdrawn" | "orderClosed";

export interface DeliveryPoolListingDoc {
  organizationId: string;
  branchId: string;
  branchName: string;
  orderId: string;
  orderNumber: string;
  districtId: string;
  neighborhoodName: string;
  /** Street, building, apartment, floor and directions — never phone/name. */
  addressLine: string;
  amountDueMinorUnits: number;
  currencyCode: string;
  plannedPaymentMethodId: string | null;
  status: PoolListingStatus;
  assignedCourierId: string | null;
  publishedAt: Timestamp;
  publishedByUid: string;
  updatedAt: Timestamp;
}

export interface CourierPoolRequestDoc {
  organizationId: string;
  branchId: string;
  orderId: string;
  orderNumber: string;
  courierId: string;
  courierName: string;
  courierAuthUid: string;
  districtId: string;
  neighborhoodName: string;
  amountDueMinorUnits: number;
  status: PoolRequestStatus;
  rejection: PoolRequestRejection | null;
  createdAt: Timestamp;
  respondedAt: Timestamp | null;
  respondedByUid: string | null;
}

export interface CourierAccountDoc {
  organizationId: string;
  courierId: string;
  type: string;
  serviceDistrictIds: string[];
  status: string;
  updatedAt: Timestamp;
}

export function poolRequestId(orderId: string, courierId: string): string {
  return `${orderId}_${courierId}`;
}

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) invalid(`${field} is required.`);
  return (raw as string).trim();
}

function actorRolesFor(request: CallableRequest, organizationId: string): string[] | null {
  const roles = (request.auth?.token.roles as Record<string, unknown> | undefined)?.[organizationId];
  return Array.isArray(roles) ? (roles as string[]) : null;
}

function nonEmpty(...parts: unknown[]): string[] {
  return parts.filter((p): p is string => typeof p === "string" && p.trim().length > 0).map((p) => p.trim());
}

/** The open address a courier needs — neighborhood excluded (shown apart). */
export function poolAddressLine(address: DocumentData | undefined): string {
  if (!address) return "";
  const street = nonEmpty(address.streetName, address.buildingNo ? `No: ${address.buildingNo}` : null).join(" ");
  return nonEmpty(
    street,
    address.apartmentNo ? `Daire: ${address.apartmentNo}` : null,
    address.floor ? `Kat: ${address.floor}` : null,
    address.addressDescription,
  ).join(", ");
}

/**
 * The order's pool region (district slug): the address's own `districtId`;
 * else the branch's enabled service area for the address's neighborhood;
 * else the branch's `defaultDeliveryDistrictId`; else `null` (publishing
 * then fails — a package nobody can see must not look published).
 */
export async function resolvePoolDistrictId(
  tx: Transaction,
  db: Firestore,
  order: DocumentData,
  branch: DocumentData,
): Promise<string | null> {
  const address = order.deliveryAddressSnapshot as DocumentData | undefined;
  const own = typeof address?.districtId === "string" ? address.districtId.trim() : "";
  if (own.length > 0) return own;
  const neighborhood = typeof address?.neighborhoodName === "string" ? slugifyAddressComponent(address.neighborhoodName) : "";
  if (neighborhood.length > 0) {
    const areas = await tx.get(
      db.collection(DELIVERY_SERVICE_AREAS_COLLECTION)
        .where("branchId", "==", order.branchId)
        .where("neighborhoodId", "==", neighborhood)
        .where("enabled", "==", true),
    );
    const districts = new Set(areas.docs.map((d) => String(d.data().districtId ?? "")).filter((d) => d.length > 0));
    if (districts.size === 1) return [...districts][0];
  }
  const fallback = typeof branch.defaultDeliveryDistrictId === "string" ? branch.defaultDeliveryDistrictId.trim() : "";
  return fallback.length > 0 ? fallback : null;
}

async function authorizeDispatch(request: CallableRequest, orderId: string, db: Firestore) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const orderRef = db.collection("orders").doc(orderId);
  const snap = await orderRef.get();
  if (!snap.exists) throw new HttpsError("not-found", "Order not found.");
  const order = snap.data()!;
  const organizationId = order.organizationId as string;
  const branchId = order.branchId as string;
  await requireStaffPermission(request, organizationId, "manageCourierDispatch");
  await requireBranchAccess(request, organizationId, branchId);
  return { orderRef, organizationId, branchId };
}

/** "Havuza Gönder". Idempotent for an already-open listing. */
export const publishOrderToPool = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const orderId = requireString(data.orderId, "orderId");
  const db = getFirestore();
  const { orderRef, organizationId, branchId } = await authorizeDispatch(request, orderId, db);
  const listingRef = db.collection(DELIVERY_POOL_LISTINGS_COLLECTION).doc(orderId);
  const branchRef = db.collection("branches").doc(branchId);
  const uid = request.auth!.uid;

  return db.runTransaction(async (tx) => {
    const orderSnap = await tx.get(orderRef);
    const order = orderSnap.data()!;
    const listingSnap = await tx.get(listingRef);
    const branchSnap = await tx.get(branchRef);
    if (order.channel !== "delivery") {
      throw new HttpsError("failed-precondition", "This order is not a delivery order.");
    }
    if (listingSnap.exists && listingSnap.data()!.status === "open") {
      return { orderId, districtId: listingSnap.data()!.districtId as string, duplicate: true };
    }
    if (!PUBLISHABLE_STATUSES.has(order.status as string)) {
      throw new HttpsError("failed-precondition", `Order cannot be published to the pool (status: "${order.status}").`, {
        code: "courierPool/not-publishable",
      });
    }
    if (order.assignedCourierId || order.poolReservedCourierId) {
      throw new HttpsError("failed-precondition", "The order already has a courier.", { code: "courierPool/already-assigned" });
    }
    const branch = branchSnap.exists ? branchSnap.data()! : {};
    const districtId = await resolvePoolDistrictId(tx, db, order, branch);
    if (!districtId) {
      throw new HttpsError("failed-precondition", "The delivery region (district) of this order could not be determined.", {
        code: "courierPool/district-unresolved",
      });
    }
    const now = Timestamp.now();
    const address = order.deliveryAddressSnapshot as DocumentData | undefined;
    const listing: DeliveryPoolListingDoc = {
      organizationId,
      branchId,
      branchName: (branch.name as string | undefined) ?? "",
      orderId,
      orderNumber: String(order.orderNumber ?? orderId),
      districtId,
      neighborhoodName: (address?.neighborhoodName as string | undefined) ?? "",
      addressLine: poolAddressLine(address),
      amountDueMinorUnits: orderAmountDueMinorUnits(order),
      currencyCode: (order.pricing?.grandTotal?.currencyCode as string | undefined) ?? "TRY",
      plannedPaymentMethodId: (order.paymentMethodSnapshot?.paymentMethodId as string | undefined) ?? null,
      status: "open",
      assignedCourierId: null,
      publishedAt: now,
      publishedByUid: uid,
      updatedAt: now,
    };
    tx.set(listingRef, listing);
    tx.set(orderRef, { poolStatus: "published", poolDistrictId: districtId }, { merge: true });
    writeAuditEvent({
      tx, db, eventId: `courierPool-${orderId}-published-${now.toMillis()}`, organizationId, branchId,
      type: "courierPool.published", targetRef: listingRef.path, newValue: { orderId, districtId },
      actorType: "staff", actorUid: uid, actorRoles: actorRolesFor(request, organizationId),
      correlationId: generateCorrelationId(), now,
    });
    return { orderId, districtId, duplicate: false };
  });
});

async function pendingRequestsFor(tx: Transaction, db: Firestore, orderId: string) {
  return tx.get(
    db.collection(COURIER_POOL_REQUESTS_COLLECTION).where("orderId", "==", orderId).where("status", "==", "pending"),
  );
}

/** "Havuzdan Geri Al": the listing closes and every pending request is rejected. */
export const withdrawOrderFromPool = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const orderId = requireString(data.orderId, "orderId");
  const db = getFirestore();
  const { orderRef, organizationId, branchId } = await authorizeDispatch(request, orderId, db);
  const listingRef = db.collection(DELIVERY_POOL_LISTINGS_COLLECTION).doc(orderId);
  const uid = request.auth!.uid;

  return db.runTransaction(async (tx) => {
    const listingSnap = await tx.get(listingRef);
    const pending = await pendingRequestsFor(tx, db, orderId);
    if (!listingSnap.exists || listingSnap.data()!.status !== "open") {
      throw new HttpsError("failed-precondition", "The order is not open in the pool.", { code: "courierPool/not-open" });
    }
    const now = Timestamp.now();
    tx.update(listingRef, { status: "withdrawn", updatedAt: now });
    for (const doc of pending.docs) {
      tx.update(doc.ref, { status: "rejected", rejection: "withdrawn", respondedAt: now, respondedByUid: uid });
    }
    tx.set(orderRef, { poolStatus: null }, { merge: true });
    writeAuditEvent({
      tx, db, eventId: `courierPool-${orderId}-withdrawn-${now.toMillis()}`, organizationId, branchId,
      type: "courierPool.withdrawn", targetRef: listingRef.path, newValue: { orderId, rejectedRequests: pending.size },
      actorType: "staff", actorUid: uid, actorRoles: actorRolesFor(request, organizationId),
      correlationId: generateCorrelationId(), now,
    });
    return { orderId, rejectedRequests: pending.size };
  });
});

/**
 * The calling courier's account (`courierAccounts/{uid}`, written by
 * `setCourier` when an auth account is linked) and courier doc.
 */
async function requireCourierAccount(request: CallableRequest, tx: Transaction, db: Firestore) {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const uid = request.auth.uid;
  const accountSnap = await tx.get(db.collection(COURIER_ACCOUNTS_COLLECTION).doc(uid));
  if (!accountSnap.exists) throw new HttpsError("permission-denied", "This account is not a registered courier.");
  const account = accountSnap.data() as CourierAccountDoc;
  const organizationAccess = request.auth.token.organizationAccess;
  if (!Array.isArray(organizationAccess) || !organizationAccess.includes(account.organizationId)) {
    throw new HttpsError("permission-denied", "This account is not a member of the courier's organization.");
  }
  const courierRef = db.collection("couriers").doc(account.courierId);
  const courierSnap = await tx.get(courierRef);
  if (!courierSnap.exists) throw new HttpsError("permission-denied", "This account is not a registered courier.");
  const courier = courierSnap.data()!;
  if ((courier.status ?? "active") !== "active" || courier.authUid !== uid) {
    throw new HttpsError("permission-denied", "This courier account is not active.");
  }
  return { uid, account, courierRef, courierId: account.courierId, courier };
}

/** An external courier's "Talep Oluştur". Idempotent per (order, courier). */
export const requestPoolOrder = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const orderId = requireString(data.orderId, "orderId");
  const db = getFirestore();
  const listingRef = db.collection(DELIVERY_POOL_LISTINGS_COLLECTION).doc(orderId);

  return db.runTransaction(async (tx) => {
    const { uid, courierId, courier } = await requireCourierAccount(request, tx, db);
    const requestRef = db.collection(COURIER_POOL_REQUESTS_COLLECTION).doc(poolRequestId(orderId, courierId));
    const listingSnap = await tx.get(listingRef);
    const existing = await tx.get(requestRef);
    if (courier.type !== "pool") {
      throw new HttpsError("permission-denied", "Only external couriers can request pool packages.", { code: "courierPool/not-external" });
    }
    if (!listingSnap.exists) throw new HttpsError("not-found", "Package not found in the pool.");
    const listing = listingSnap.data() as DeliveryPoolListingDoc;
    const districts: string[] = Array.isArray(courier.serviceDistrictIds) ? courier.serviceDistrictIds : [];
    if (listing.organizationId !== courier.organizationId || !districts.includes(listing.districtId)) {
      throw new HttpsError("not-found", "Package not found in the pool.");
    }
    if (listing.status !== "open") {
      throw new HttpsError("failed-precondition", "This package is no longer in the pool.", { code: "courierPool/not-open" });
    }
    if (existing.exists && existing.data()!.status === "pending") {
      return { requestId: requestRef.id, duplicate: true };
    }
    const now = Timestamp.now();
    const doc: CourierPoolRequestDoc = {
      organizationId: listing.organizationId,
      branchId: listing.branchId,
      orderId,
      orderNumber: listing.orderNumber,
      courierId,
      courierName: (courier.displayName as string | undefined) ?? courierId,
      courierAuthUid: uid,
      districtId: listing.districtId,
      neighborhoodName: listing.neighborhoodName,
      amountDueMinorUnits: listing.amountDueMinorUnits,
      status: "pending",
      rejection: null,
      createdAt: now,
      respondedAt: null,
      respondedByUid: null,
    };
    tx.set(requestRef, doc);
    return { requestId: requestRef.id, duplicate: false };
  });
});

/**
 * Approve or reject an external courier's pool request. Approval assigns
 * (ready order) or reserves (still being prepared) the package for that
 * courier and rejects every other pending request for it.
 */
export const respondToCourierPoolRequest = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const requestId = requireString(data.requestId, "requestId");
  const decision = requireString(data.decision, "decision");
  if (decision !== "approve" && decision !== "reject") invalid('decision must be "approve" or "reject".');
  const db = getFirestore();
  const requestRef = db.collection(COURIER_POOL_REQUESTS_COLLECTION).doc(requestId);
  const preSnap = await requestRef.get();
  if (!preSnap.exists) throw new HttpsError("not-found", "Request not found.");
  const pre = preSnap.data() as CourierPoolRequestDoc;
  await requireStaffPermission(request, pre.organizationId, "approveCourierPoolRequests");
  await requireBranchAccess(request, pre.organizationId, pre.branchId);
  const uid = request.auth.uid;

  return db.runTransaction(async (tx) => {
    const reqSnap = await tx.get(requestRef);
    const req = reqSnap.data() as CourierPoolRequestDoc;
    const orderRef = db.collection("orders").doc(req.orderId);
    const listingRef = db.collection(DELIVERY_POOL_LISTINGS_COLLECTION).doc(req.orderId);
    const courierRef = db.collection("couriers").doc(req.courierId);
    const orderSnap = await tx.get(orderRef);
    const listingSnap = await tx.get(listingRef);
    const courierSnap = await tx.get(courierRef);
    const pending = await pendingRequestsFor(tx, db, req.orderId);

    if (req.status !== "pending") {
      throw new HttpsError("failed-precondition", "This request was already answered.", { code: "courierPool/request-answered" });
    }
    const now = Timestamp.now();
    const actorRoles = actorRolesFor(request, req.organizationId);

    if (decision === "reject") {
      tx.update(requestRef, { status: "rejected", rejection: "rejected", respondedAt: now, respondedByUid: uid });
      writeAuditEvent({
        tx, db, eventId: `courierPool-${requestId}-rejected`, organizationId: req.organizationId, branchId: req.branchId,
        type: "courierPool.requestRejected", targetRef: requestRef.path, newValue: { orderId: req.orderId, courierId: req.courierId },
        actorType: "staff", actorUid: uid, actorRoles, correlationId: generateCorrelationId(), now,
      });
      return { requestId, decision, orderStatus: null };
    }

    if (!listingSnap.exists || listingSnap.data()!.status !== "open") {
      throw new HttpsError("failed-precondition", "This package is no longer in the pool.", { code: "courierPool/not-open" });
    }
    if (!orderSnap.exists) throw new HttpsError("not-found", "Order not found.");
    const order = orderSnap.data()!;
    if (!courierSnap.exists) throw new HttpsError("not-found", "Courier not found.");
    const courier = courierSnap.data()!;
    if (courier.type !== "pool" || !courierCanServeOrder(courier, req.organizationId, req.branchId)) {
      throw new HttpsError("failed-precondition", "This courier can no longer take pool packages.", { code: "courierPool/courier-inactive" });
    }
    if (order.assignedCourierId || order.poolReservedCourierId) {
      throw new HttpsError("failed-precondition", "The order already has a courier.", { code: "courierPool/already-assigned" });
    }
    const status = order.status as OrderStatus;
    const ready = status === "ready" || status === "readyForPickup";
    if (!ready && !PUBLISHABLE_STATUSES.has(status)) {
      throw new HttpsError("failed-precondition", `Order cannot be handed to a courier (status: "${status}").`, {
        code: "courierPool/not-publishable",
      });
    }

    const courierName = (courier.displayName as string | undefined) ?? req.courierId;
    let orderStatus: string = status;
    if (ready && canTransition(status, "outForDelivery")) {
      orderStatus = applyCourierAssignment({
        tx, db, request, orderRef, orderId: req.orderId, order,
        organizationId: req.organizationId, branchId: req.branchId,
        courierRef, courierId: req.courierId, courier, previousCourier: null, now,
      }).status;
      tx.set(orderRef, { poolStatus: "assigned", plannedCourierId: req.courierId, plannedCourierName: courierName }, { merge: true });
    } else {
      // Still being prepared — reserved for this courier; the one-tap
      // "<kurye> Ata" on the dispatch board assigns it once it is ready.
      tx.set(orderRef, {
        poolStatus: "assigned",
        poolReservedCourierId: req.courierId,
        plannedCourierId: req.courierId,
        plannedCourierName: courierName,
      }, { merge: true });
    }
    tx.update(listingRef, { status: "assigned", assignedCourierId: req.courierId, updatedAt: now });
    tx.update(requestRef, { status: "approved", rejection: null, respondedAt: now, respondedByUid: uid });
    let otherRejected = 0;
    for (const doc of pending.docs) {
      if (doc.id === requestId) continue;
      otherRejected += 1;
      tx.update(doc.ref, { status: "rejected", rejection: "otherApproved", respondedAt: now, respondedByUid: uid });
    }
    writeAuditEvent({
      tx, db, eventId: `courierPool-${requestId}-approved`, organizationId: req.organizationId, branchId: req.branchId,
      type: "courierPool.requestApproved", targetRef: requestRef.path,
      newValue: { orderId: req.orderId, courierId: req.courierId, otherRejected, orderStatus },
      actorType: "staff", actorUid: uid, actorRoles, correlationId: generateCorrelationId(), now,
    });
    return { requestId, decision, orderStatus, otherRejected };
  });
});

async function loadCourierOrder(request: CallableRequest, tx: Transaction, db: Firestore, orderId: string) {
  const who = await requireCourierAccount(request, tx, db);
  const orderRef = db.collection("orders").doc(orderId);
  const projectionRef = db.collection(COURIER_ASSIGNED_ORDERS_COLLECTION).doc(orderId);
  const orderSnap = await tx.get(orderRef);
  const projectionSnap = await tx.get(projectionRef);
  if (!orderSnap.exists) throw new HttpsError("not-found", "Order not found.");
  const order = orderSnap.data()!;
  if (order.assignedCourierId !== who.courierId || order.organizationId !== who.account.organizationId) {
    throw new HttpsError("permission-denied", "This order is not assigned to you.");
  }
  if (order.status !== "outForDelivery") {
    throw new HttpsError("failed-precondition", `The order is not out for delivery (status: "${order.status}").`, {
      code: "courierPool/not-out-for-delivery",
    });
  }
  return { ...who, orderRef, order, projectionRef, projectionSnap };
}

/** "Yola Çıktım" — records `departedAt` only (no status change). Idempotent. */
export const courierMarkDeparted = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const orderId = requireString(data.orderId, "orderId");
  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { orderRef, order, projectionRef, projectionSnap } = await loadCourierOrder(request, tx, db, orderId);
    if (order.departedAt) return { orderId, duplicate: true };
    const now = Timestamp.now();
    tx.set(orderRef, { departedAt: now }, { merge: true });
    if (projectionSnap.exists) tx.update(projectionRef, { departedAt: now, status: "departed", updatedAt: now });
    return { orderId, duplicate: false };
  });
});

/**
 * "Teslim Ettim" with the method the customer really paid. The order stays
 * `outForDelivery` ("Teslim Edildi — Mutabakat Bekliyor") until the POS
 * settlement; the courier's copy of the customer phone is removed now.
 */
export const courierReportDelivered = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const orderId = requireString(data.orderId, "orderId");
  const paymentMethodId = requireString(data.paymentMethodId, "paymentMethodId");
  if (!STAFF_DELIVERY_PAYMENT_METHOD_IDS.has(paymentMethodId)) {
    invalid(`paymentMethodId "${paymentMethodId}" is not a pay-on-delivery method.`);
  }
  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { uid, courierId, orderRef, order, projectionRef, projectionSnap } = await loadCourierOrder(request, tx, db, orderId);
    if (order.courierReportedDeliveredAt) return { orderId, duplicate: true };
    const now = Timestamp.now();
    tx.set(orderRef, {
      courierReportedDeliveredAt: now,
      courierReportedPaymentMethodId: paymentMethodId,
      ...(order.departedAt ? {} : { departedAt: now }),
    }, { merge: true });
    if (projectionSnap.exists) {
      const projection = { ...projectionSnap.data()! };
      delete projection.customerPhone;
      tx.set(projectionRef, {
        ...projection,
        status: "deliveredAwaitingSettlement",
        deliveredAt: now,
        reportedPaymentMethodId: paymentMethodId,
        updatedAt: now,
      });
    }
    writeAuditEvent({
      tx, db, eventId: `courierDelivery-${orderId}-reported`, organizationId: order.organizationId as string,
      branchId: order.branchId as string, type: "courierDelivery.reported", targetRef: orderRef.path,
      previousValue: { paymentMethodId: (order.paymentMethodSnapshot?.paymentMethodId as string | undefined) ?? null },
      newValue: { courierId, paymentMethodId },
      actorType: "courier", actorUid: uid, actorRoles: actorRolesFor(request, order.organizationId as string),
      correlationId: generateCorrelationId(), now,
    });
    return { orderId, duplicate: false };
  });
});

export type CourierProjectionStatus = "reserved" | "assigned" | "departed" | "deliveredAwaitingSettlement";

/**
 * The courier's own copy of an order — `null` when no courier holds it any
 * more (closed/cancelled, or unassigned). Pure, so its KVKK rule (no phone
 * once delivered) is unit-testable.
 */
export function buildCourierAssignedOrderProjection(
  orderId: string,
  order: DocumentData,
  courierAuthUid: string | null,
): Record<string, unknown> | null {
  if (order.channel !== "delivery" || CLOSED_STATUSES.has(order.status as string)) return null;
  const assigned = order.assignedCourierId as string | undefined;
  const reserved = order.poolReservedCourierId as string | undefined;
  const courierId = assigned ?? reserved;
  if (!courierId) return null;
  const delivered = Boolean(order.courierReportedDeliveredAt);
  const status: CourierProjectionStatus = delivered
    ? "deliveredAwaitingSettlement"
    : !assigned
      ? "reserved"
      : order.departedAt
        ? "departed"
        : "assigned";
  const address = order.deliveryAddressSnapshot as DocumentData | undefined;
  return {
    organizationId: order.organizationId,
    branchId: order.branchId,
    orderId,
    orderNumber: String(order.orderNumber ?? orderId),
    courierId,
    courierAuthUid,
    customerName: nonEmpty(order.contactFirstName, order.contactLastName).join(" "),
    ...(delivered ? {} : { customerPhone: (order.contactPhone as string | undefined) ?? null }),
    neighborhoodName: (address?.neighborhoodName as string | undefined) ?? "",
    addressLine: poolAddressLine(address),
    courierNote: (order.customerNote as string | undefined) ?? "",
    amountDueMinorUnits: orderAmountDueMinorUnits(order),
    plannedPaymentMethodId: (order.paymentMethodSnapshot?.paymentMethodId as string | undefined) ?? null,
    reportedPaymentMethodId: (order.courierReportedPaymentMethodId as string | undefined) ?? null,
    status,
    departedAt: order.departedAt ?? null,
    deliveredAt: order.courierReportedDeliveredAt ?? null,
  };
}

const PROJECTION_INPUT_FIELDS = [
  "status", "assignedCourierId", "poolReservedCourierId", "poolStatus", "departedAt",
  "courierReportedDeliveredAt", "courierReportedPaymentMethodId", "contactPhone",
  "contactFirstName", "contactLastName", "deliveryAddressSnapshot", "customerNote",
] as const;

function projectionInputsChanged(before: DocumentData, after: DocumentData): boolean {
  return PROJECTION_INPUT_FIELDS.some((f) => JSON.stringify(before[f] ?? null) !== JSON.stringify(after[f] ?? null));
}

/**
 * Keeps `courierAssignedOrders/{orderId}` in step with the order (assign,
 * reassign, batch assign, reserve, departure, delivery report, settlement,
 * cancellation), and closes a still-open pool listing once the order got a
 * courier some other way (direct assignment) or closed.
 */
export async function syncCourierProjectionForOrder(
  db: Firestore,
  orderRef: DocumentReference,
  order: DocumentData,
): Promise<void> {
  if (order.channel !== "delivery") return;
  const orderId = orderRef.id;
  const projectionRef = db.collection(COURIER_ASSIGNED_ORDERS_COLLECTION).doc(orderId);
  const courierId = (order.assignedCourierId as string | undefined) ?? (order.poolReservedCourierId as string | undefined);
  let authUid: string | null = null;
  if (courierId) {
    const courierSnap = await db.collection("couriers").doc(courierId).get();
    authUid = courierSnap.exists ? ((courierSnap.data()!.authUid as string | undefined) ?? null) : null;
  }
  const projection = buildCourierAssignedOrderProjection(orderId, order, authUid);
  if (projection) {
    await projectionRef.set({ ...projection, updatedAt: Timestamp.now() });
  } else {
    await projectionRef.delete();
  }

  const closed = CLOSED_STATUSES.has(order.status as string);
  if (order.poolStatus === "published" && (closed || order.assignedCourierId)) {
    const now = Timestamp.now();
    const batch = db.batch();
    const listingRef = db.collection(DELIVERY_POOL_LISTINGS_COLLECTION).doc(orderId);
    const listing = await listingRef.get();
    if (listing.exists && listing.data()!.status === "open") {
      batch.update(listingRef, {
        status: closed ? "closed" : "assigned",
        assignedCourierId: closed ? null : order.assignedCourierId,
        updatedAt: now,
      });
    }
    const pending = await db.collection(COURIER_POOL_REQUESTS_COLLECTION)
      .where("orderId", "==", orderId).where("status", "==", "pending").get();
    for (const doc of pending.docs) {
      batch.update(doc.ref, { status: "rejected", rejection: "orderClosed", respondedAt: now, respondedByUid: null });
    }
    batch.set(orderRef, { poolStatus: closed ? "closed" : "assigned" }, { merge: true });
    await batch.commit();
  }
}

export const onDeliveryOrderCourierProjection = onDocumentUpdated("orders/{orderId}", async (event) => {
  const before = event.data?.before?.data();
  const after = event.data?.after?.data();
  if (!before || !after || after.channel !== "delivery") return;
  if (!projectionInputsChanged(before, after)) return;
  await syncCourierProjectionForOrder(getFirestore(), event.data!.after.ref, after);
});
