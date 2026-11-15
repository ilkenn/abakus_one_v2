import { createHash } from "crypto";
import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { getFirestore, Timestamp, type DocumentData, type Firestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId } from "./correlationId";
import { DELIVERY_PAYMENT_METHOD_CATALOG } from "./deliveryPaymentMethodCatalog";
import { STAFF_DELIVERY_PAYMENT_METHOD_IDS } from "./submitStaffDeliveryOrder";
import { orderAmountDueMinorUnits } from "./courierSettlement";
import { COURIER_PII_FIELDS, actorRolesFor, loadCourierOrder } from "./courierPool";
import { COURIER_UPLOAD_GRANTS_COLLECTION, type CourierUploadGrantDoc } from "./courierInvoices";
import { resolveStaffScope, type StaffScope } from "./staffScope";
import { roleHasPermission } from "./staffAuthorization";
import { canTransition, type OrderStatus } from "./orderStatus";
import { applyDeliveryLifecycleTransition, writeDeliveryOrderStatusChangeAuditEvent } from "./deliveryOrderLifecycle";
import { prepareCancellationStockHandling, applyCancellationStockHandling } from "./cancelOrderLineStock";
import { buildApprovalRequestRecord, type ActionHandlerParams, type ActionHandlerResult } from "./remoteApproval";
import { deliverCourierNotification } from "./courierNotifications";
import { applyCarriedCash, courierOperationSettingsOf, lateAlertRef, resolveAlert } from "./courierFieldAlerts";

/**
 * ADR-085 stage 6B (product owner approved 2026-11-15) — safety at the door.
 *
 * - **"Teslim Ettim" payment rules** ([courierReportDelivered], moved here
 *   from `courierPool.ts`): the courier may switch between the
 *   pay-on-delivery methods only (cash, card on the POS, Pluxee, Multinet,
 *   Edenred, Setcard, MetropolCard). An order paid online can never be
 *   switched, and nothing can be switched to online.
 * - **Slip photo**: every card or meal-card collection needs a photo taken
 *   with the camera (the app offers no gallery) of the POS slip or the
 *   meal-card approval, uploaded under a one-use grant for that order
 *   (`requestCourierUploadGrant`, purpose `paymentSlip`) at most 15 minutes
 *   before "Teslim Ettim". The server checks the photo is really there.
 * - **Change review**: a changed method writes `courierPaymentChanges/
 *   {orderId}` (old → new, courier, time, slip) and an audit event, and
 *   notifies the managers, admins and owners; a manager of the branch or an
 *   admin/owner marks it reviewed ("İncelendi") after looking at the slip.
 * - **Cancellation request**: a courier never cancels (no staff permission
 *   at all). It sends a reason ("İptal Talebi Gönder"); the request lands in
 *   the Onay Kutusu (`courierOrderCancellation`) for a manager of the branch
 *   or an admin/owner; unanswered for 24 hours it escalates to the platform
 *   owner like every other approval. Approval cancels the order through the
 *   same lifecycle as a staff cancellation; rejection keeps the delivery.
 */
export const COURIER_PAYMENT_CHANGES_COLLECTION = "courierPaymentChanges";
export const COURIER_CANCELLATION_REQUESTS_COLLECTION = "courierCancellationRequests";

const SLIP_MAX_AGE_MS = 15 * 60 * 1000;
const MAX_FILE_BYTES = 5 * 1024 * 1024;
const MAX_REASON_LENGTH = 300;
const MIN_REASON_LENGTH = 5;

export interface CourierPaymentChangeDoc {
  organizationId: string;
  branchId: string;
  orderId: string;
  orderNumber: string;
  courierId: string;
  courierUid: string;
  courierName: string;
  fromMethodId: string | null;
  toMethodId: string;
  amountDueMinorUnits: number;
  slipPath: string | null;
  status: "pendingReview" | "reviewed";
  reportedAt: Timestamp;
  reviewedByUid: string | null;
  reviewedAt: Timestamp | null;
  reviewNote: string | null;
}

export interface CourierCancellationRequestDoc {
  organizationId: string;
  branchId: string;
  orderId: string;
  orderNumber: string;
  courierId: string;
  courierUid: string;
  courierName: string;
  reason: string;
  status: "pending" | "approved" | "rejected";
  attempt: number;
  approvalRequestId: string;
  createdAt: Timestamp;
  decidedByUid: string | null;
  decidedAt: Timestamp | null;
}

function invalid(message: string, code?: string): never {
  throw new HttpsError("invalid-argument", message, code ? { code } : undefined);
}

function precondition(message: string, code: string): never {
  throw new HttpsError("failed-precondition", message, { code });
}

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) invalid(`${field} is required.`);
  return (raw as string).trim();
}

function optionalString(raw: unknown): string | null {
  return typeof raw === "string" && raw.trim().length > 0 ? raw.trim() : null;
}

// ---------------------------------------------------------------------------
// Pure rules
// ---------------------------------------------------------------------------

/** A card on the POS or a meal card: the courier must photograph the slip. */
export function paymentNeedsSlip(paymentMethodId: string): boolean {
  const category = DELIVERY_PAYMENT_METHOD_CATALOG[paymentMethodId]?.reportingCategory;
  return category === "card" || category === "mealCard";
}

export function isPayOnDelivery(paymentMethodId: string | null | undefined): boolean {
  return typeof paymentMethodId === "string" && STAFF_DELIVERY_PAYMENT_METHOD_IDS.has(paymentMethodId);
}

/**
 * Which method "Teslim Ettim" records. Pay-on-delivery orders: any
 * pay-on-delivery method (a different one is a change to review). An order
 * paid online: no method, or the same one — never a change.
 */
export function resolveDeliveryPayment(planned: string | null, reported: string | null) {
  if (planned !== null && !isPayOnDelivery(planned)) {
    if (reported !== null && reported !== planned) {
      throw new HttpsError("failed-precondition", "An order paid online cannot change its payment method.", {
        code: "courierDelivery/online-payment-locked",
      });
    }
    return { methodId: planned, changed: false, needsSlip: false, collected: false };
  }
  if (reported === null || !isPayOnDelivery(reported)) {
    invalid(`paymentMethodId must be one of: ${[...STAFF_DELIVERY_PAYMENT_METHOD_IDS].join(", ")}.`, "courierDelivery/invalid-method");
  }
  return {
    methodId: reported as string,
    changed: planned !== null && planned !== reported,
    needsSlip: paymentNeedsSlip(reported as string),
    collected: true,
  };
}

// ---------------------------------------------------------------------------
// "Teslim Ettim"
// ---------------------------------------------------------------------------

/**
 * "Teslim Ettim" with the method the customer really paid (and, for a card
 * or meal card, the slip photo). The order stays `outForDelivery` ("Teslim
 * Edildi — Mutabakat Bekliyor") until the POS settlement; the courier's copy
 * loses the customer's personal data now (KVKK — `COURIER_PII_FIELDS`).
 */
export const courierReportDelivered = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const orderId = requireString(data.orderId, "orderId");
  const reported = optionalString(data.paymentMethodId);
  const slipGrantId = optionalString(data.slipGrantId);
  const uid = request.auth.uid;
  const db = getFirestore();
  const orderRef = db.collection("orders").doc(orderId);

  // Outside the transaction: the slip photo must really be in Storage.
  const preOrder = await orderRef.get();
  if (!preOrder.exists) throw new HttpsError("not-found", "Order not found.");
  const prePlanned = (preOrder.data()!.paymentMethodSnapshot?.paymentMethodId as string | undefined) ?? null;
  const preDecision = resolveDeliveryPayment(prePlanned, reported);
  let slip: { ref: FirebaseFirestore.DocumentReference; grant: CourierUploadGrantDoc } | null = null;
  if (preDecision.needsSlip) {
    if (!slipGrantId) precondition("A photo of the slip is required for a card or meal-card payment.", "courierDelivery/slip-required");
    const grantRef = db.collection(COURIER_UPLOAD_GRANTS_COLLECTION).doc(slipGrantId as string);
    const grantSnap = await grantRef.get();
    const grant = grantSnap.data() as CourierUploadGrantDoc | undefined;
    if (!grant || grant.staffUid !== uid || grant.purpose !== "paymentSlip" || grant.orderId !== orderId) {
      precondition("The slip photo does not belong to this order.", "courierDelivery/slip-invalid");
    }
    if (Date.now() - grant!.createdAt.toMillis() > SLIP_MAX_AGE_MS) {
      precondition("The slip photo is too old; take a new one.", "courierDelivery/slip-expired");
    }
    let metadata: { size?: string | number; contentType?: string };
    try {
      [metadata] = await getStorage().bucket().file(grant!.objectPath).getMetadata();
    } catch {
      precondition("The slip photo has not been uploaded.", "courierDelivery/slip-missing");
    }
    if (Number(metadata!.size ?? 0) > MAX_FILE_BYTES || !String(metadata!.contentType ?? "").startsWith("image/")) {
      precondition("The slip photo is not a valid image.", "courierDelivery/slip-invalid");
    }
    slip = { ref: grantRef, grant: grant! };
  }

  const result = await db.runTransaction(async (tx) => {
    const { courierId, courier, courierRef, order, projectionRef, projectionSnap } = await loadCourierOrder(request, tx, db, orderId);
    if (order.courierReportedDeliveredAt) return { orderId, duplicate: true, changed: false };
    // Stage 6C-1 — a pool courier collects at the counter ("Teslim Et") first.
    if (order.courierType === "pool" && !order.packingVerifiedAt) {
      precondition("Collect the package at the counter first.", "courierPool/not-handed-over");
    }
    const branchSnap = await tx.get(db.collection("branches").doc(String(order.branchId)));
    const planned = (order.paymentMethodSnapshot?.paymentMethodId as string | undefined) ?? null;
    const decision = resolveDeliveryPayment(planned, reported);
    if (decision.needsSlip && !slip) precondition("A photo of the slip is required.", "courierDelivery/slip-required");
    if (slip) {
      const fresh = await tx.get(slip.ref);
      if ((fresh.data() as CourierUploadGrantDoc | undefined)?.status !== "issued") {
        precondition("This slip photo was already used; take a new one.", "courierDelivery/slip-used");
      }
    }
    const organizationId = order.organizationId as string;
    const branchId = order.branchId as string;
    const now = Timestamp.now();
    tx.set(orderRef, {
      courierReportedDeliveredAt: now,
      courierReportedPaymentMethodId: decision.collected ? decision.methodId : null,
      courierPaymentSlipPath: slip ? slip.grant.objectPath : null,
      ...(order.departedAt ? {} : { departedAt: now }),
    }, { merge: true });
    if (slip) tx.update(slip.ref, { status: "used" });
    // Stage 6C-1 — cash the courier now carries; the late alert closes.
    let cashState: { carriedMinorUnits: number; exceeded: boolean } | null = null;
    if (decision.collected && decision.methodId === "cash") {
      cashState = applyCarriedCash(tx, db, {
        organizationId, branchId, courierRef, courier, courierUid: uid, order,
        settings: courierOperationSettingsOf(branchSnap.data()), now,
      });
    }
    if (order.courierLateAt) resolveAlert(tx, lateAlertRef(db, orderId), now);
    if (projectionSnap.exists) {
      const projection = { ...projectionSnap.data()! };
      for (const field of COURIER_PII_FIELDS) delete projection[field];
      tx.set(projectionRef, {
        ...projection,
        status: "deliveredAwaitingSettlement",
        deliveredAt: now,
        reportedPaymentMethodId: decision.collected ? decision.methodId : null,
        updatedAt: now,
      });
    }
    const actorRoles = actorRolesFor(request, organizationId);
    writeAuditEvent({
      tx, db, eventId: `courierDelivery-${orderId}-reported`, organizationId, branchId,
      type: "courierDelivery.reported", targetRef: orderRef.path,
      previousValue: { paymentMethodId: planned },
      newValue: { courierId, paymentMethodId: decision.methodId, slipPath: slip?.grant.objectPath ?? null },
      actorType: "courier", actorUid: uid, actorRoles, correlationId: generateCorrelationId(), now,
    });
    if (decision.changed) {
      const change: CourierPaymentChangeDoc = {
        organizationId, branchId, orderId,
        orderNumber: String(order.orderNumber ?? orderId),
        courierId, courierUid: uid,
        courierName: String(courier.displayName ?? ""),
        fromMethodId: planned,
        toMethodId: decision.methodId,
        amountDueMinorUnits: orderAmountDueMinorUnits(order),
        slipPath: slip?.grant.objectPath ?? null,
        status: "pendingReview",
        reportedAt: now,
        reviewedByUid: null,
        reviewedAt: null,
        reviewNote: null,
      };
      tx.set(db.collection(COURIER_PAYMENT_CHANGES_COLLECTION).doc(orderId), change);
      writeAuditEvent({
        tx, db, eventId: `courierDelivery-${orderId}-methodChanged`, organizationId, branchId,
        type: "courierDelivery.paymentMethodChanged", targetRef: orderRef.path,
        previousValue: { paymentMethodId: planned },
        newValue: { paymentMethodId: decision.methodId, slipPath: change.slipPath },
        actorType: "courier", actorUid: uid, actorRoles, correlationId: generateCorrelationId(), now,
      });
    }
    return {
      orderId, duplicate: false, changed: decision.changed,
      carriedCashMinorUnits: cashState?.carriedMinorUnits ?? null,
      cashLimitExceeded: cashState?.exceeded ?? false,
    };
  });
  return result;
});

// ---------------------------------------------------------------------------
// Change review (panel)
// ---------------------------------------------------------------------------

function inScope(scope: StaffScope, branchId: string): boolean {
  return scope.kind === "organization" || scope.branches.has(branchId);
}

function methodLabel(id: string | null): string {
  if (id === null) return "-";
  return DELIVERY_PAYMENT_METHOD_CATALOG[id]?.displayName ?? id;
}

function serializeChange(change: CourierPaymentChangeDoc) {
  return {
    orderId: change.orderId,
    orderNumber: change.orderNumber,
    branchId: change.branchId,
    courierName: change.courierName,
    fromMethodId: change.fromMethodId,
    fromMethodLabel: methodLabel(change.fromMethodId),
    toMethodId: change.toMethodId,
    toMethodLabel: methodLabel(change.toMethodId),
    amountDueMinorUnits: change.amountDueMinorUnits,
    hasSlip: change.slipPath !== null,
    status: change.status,
    reportedAtMillis: change.reportedAt.toMillis(),
    reviewNote: change.reviewNote,
  };
}

/** Panel: payment-method changes in the caller's branches (pending first). */
export const listCourierPaymentChanges = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const scope = await resolveStaffScope(request, organizationId);
  const snap = await getFirestore().collection(COURIER_PAYMENT_CHANGES_COLLECTION).where("organizationId", "==", organizationId).get();
  const changes = snap.docs
    .map((doc) => doc.data() as CourierPaymentChangeDoc)
    .filter((change) => inScope(scope, change.branchId))
    .sort((a, b) => {
      if (a.status !== b.status) return a.status === "pendingReview" ? -1 : 1;
      return b.reportedAt.toMillis() - a.reportedAt.toMillis();
    })
    .slice(0, 300)
    .map(serializeChange);
  return { organizationId, changes };
});

async function loadChangeInScope(request: CallableRequest, organizationId: string, orderId: string) {
  const scope = await resolveStaffScope(request, organizationId);
  const ref = getFirestore().collection(COURIER_PAYMENT_CHANGES_COLLECTION).doc(orderId);
  const snap = await ref.get();
  const change = snap.data() as CourierPaymentChangeDoc | undefined;
  if (!change || change.organizationId !== organizationId || !inScope(scope, change.branchId)) {
    throw new HttpsError("not-found", "Payment change not found.");
  }
  return { ref, change };
}

/** "İncelendi": a manager of the branch or an admin/owner looked at the slip. */
export const reviewCourierPaymentChange = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const orderId = requireString(data.orderId, "orderId");
  const note = optionalString(data.note);
  if (note && note.length > MAX_REASON_LENGTH) invalid("note is too long.");
  const { ref, change } = await loadChangeInScope(request, organizationId, orderId);
  if (change.courierUid === request.auth.uid) throw new HttpsError("permission-denied", "Nobody reviews their own change.");
  const db = getFirestore();
  await db.runTransaction(async (tx) => {
    const fresh = (await tx.get(ref)).data() as CourierPaymentChangeDoc;
    if (fresh.status !== "pendingReview") precondition("This change was already reviewed.", "courierPaymentChange/already-reviewed");
    const now = Timestamp.now();
    tx.update(ref, { status: "reviewed", reviewedByUid: request.auth!.uid, reviewedAt: now, reviewNote: note });
    writeAuditEvent({
      tx, db, eventId: `courierPaymentChange-${orderId}-reviewed`, organizationId, branchId: change.branchId,
      type: "courierDelivery.paymentMethodChangeReviewed", targetRef: ref.path,
      newValue: { fromMethodId: change.fromMethodId, toMethodId: change.toMethodId }, reasonMessage: note,
      actorType: "staff", actorUid: request.auth!.uid, actorRoles: actorRolesFor(request, organizationId),
      correlationId: generateCorrelationId(), now,
    });
  });
  return { organizationId, orderId, status: "reviewed" };
});

/** The slip photo of an order (base64, branch-checked) — also for unchanged card payments. */
export const getCourierPaymentSlip = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const orderId = requireString(data.orderId, "orderId");
  const scope = await resolveStaffScope(request, organizationId);
  const order = (await getFirestore().collection("orders").doc(orderId).get()).data();
  if (!order || order.organizationId !== organizationId || !inScope(scope, order.branchId as string)) {
    throw new HttpsError("not-found", "Order not found.");
  }
  const path = order.courierPaymentSlipPath as string | undefined;
  if (!path) throw new HttpsError("not-found", "This order has no slip photo.", { code: "courierDelivery/no-slip" });
  const file = getStorage().bucket().file(path);
  const [[bytes], [metadata]] = await Promise.all([file.download(), file.getMetadata()]);
  return { orderId, contentType: String(metadata.contentType ?? "image/jpeg"), base64: bytes.toString("base64") };
});

// ---------------------------------------------------------------------------
// Cancellation request
// ---------------------------------------------------------------------------

/** "İptal Talebi Gönder" — the courier asks; the Onay Kutusu decides. */
export const courierRequestCancellation = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const orderId = requireString(data.orderId, "orderId");
  const reason = requireString(data.reason, "reason");
  if (reason.length < MIN_REASON_LENGTH || reason.length > MAX_REASON_LENGTH) {
    invalid(`reason must be ${MIN_REASON_LENGTH}–${MAX_REASON_LENGTH} characters.`, "courierCancellation/invalid-reason");
  }
  const db = getFirestore();
  const requestRef = db.collection(COURIER_CANCELLATION_REQUESTS_COLLECTION).doc(orderId);
  return db.runTransaction(async (tx) => {
    const { uid, courierId, courier, orderRef, order, projectionRef, projectionSnap } = await loadCourierOrder(request, tx, db, orderId);
    const existingSnap = await tx.get(requestRef);
    if (order.courierReportedDeliveredAt) precondition("The order is already delivered.", "courierCancellation/already-delivered");
    const existing = existingSnap.exists ? (existingSnap.data() as CourierCancellationRequestDoc) : null;
    if (existing?.status === "pending") precondition("A cancellation request is already waiting.", "courierCancellation/already-pending");
    const organizationId = order.organizationId as string;
    const branchId = order.branchId as string;
    const now = Timestamp.now();
    const attempt = (existing?.attempt ?? 0) + 1;
    const orderNumber = String(order.orderNumber ?? orderId);
    const courierName = String(courier.displayName ?? "");
    const approval = buildApprovalRequestRecord(db, {
      organizationId, branchId,
      actionType: "courierOrderCancellation",
      requestedByActorUid: uid,
      targetAggregateRef: requestRef.path,
      targetAggregateVersion: attempt,
      payloadHash: createHash("sha256").update(`${orderId}|${reason}`).digest("hex"),
      summary: `${orderNumber} · ${courierName} · Gerekçe: ${reason}`,
    }, now);
    const doc: CourierCancellationRequestDoc = {
      organizationId, branchId, orderId, orderNumber, courierId, courierUid: uid, courierName,
      reason, status: "pending", attempt, approvalRequestId: approval.requestId,
      createdAt: now, decidedByUid: null, decidedAt: null,
    };
    tx.set(requestRef, doc);
    tx.set(approval.ref, approval.record);
    tx.set(orderRef, { courierCancellationStatus: "pending" }, { merge: true });
    if (projectionSnap.exists) tx.update(projectionRef, { cancellationRequestStatus: "pending", updatedAt: now });
    writeAuditEvent({
      tx, db, eventId: `courierCancellation-${orderId}-requested-${attempt}`, organizationId, branchId,
      type: "courierCancellation.requested", targetRef: orderRef.path,
      newValue: { courierId, attempt }, reasonMessage: reason,
      actorType: "courier", actorUid: uid, actorRoles: actorRolesFor(request, organizationId),
      correlationId: generateCorrelationId(), now,
    });
    return { orderId, status: "pending", approvalRequestId: approval.requestId };
  });
});

async function loadPendingCancellation(params: ActionHandlerParams) {
  const ref = params.db.doc(params.request.targetAggregateRef);
  const snap = await params.tx.get(ref);
  if (!snap.exists) throw new HttpsError("not-found", "The cancellation request no longer exists.");
  const doc = snap.data() as CourierCancellationRequestDoc;
  if (doc.status !== "pending") throw new HttpsError("failed-precondition", `The cancellation request is already "${doc.status}".`);
  return { ref, doc };
}

/** Onay Kutusu → approved: the order is cancelled like a staff cancellation. */
export async function applyCourierOrderCancellation(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, now, respondedByActorUid } = params;
  const { ref, doc } = await loadPendingCancellation(params);
  const orderRef = db.collection("orders").doc(doc.orderId);
  const orderSnap = await tx.get(orderRef);
  if (!orderSnap.exists) throw new HttpsError("not-found", "Order not found.");
  const order = orderSnap.data()!;
  const fromStatus = order.status as OrderStatus;
  if (fromStatus !== "cancelled") {
    if (!canTransition(fromStatus, "cancelled") || fromStatus === "completed" || fromStatus === "pendingConfirmation") {
      throw new HttpsError("failed-precondition", `The order cannot be cancelled from status "${fromStatus}".`);
    }
    const lines = Array.isArray(order.lines) ? order.lines : [];
    // Read phase before the first write (stock handling reads kitchen items).
    const stockPlan = await prepareCancellationStockHandling({
      tx, db, organizationId: doc.organizationId, branchId: doc.branchId, orderId: doc.orderId,
      orderLineIds: lines.map((_: unknown, index: number) => `kt-${doc.orderId}-line-${index}`),
      performedByUid: respondedByActorUid, now,
    });
    applyDeliveryLifecycleTransition({
      tx, orderRef, orderId: doc.orderId, order, fromStatus, toStatus: "cancelled",
      actorType: "staff", now, terminalReasonCode: "operationalIssue",
    });
    writeDeliveryOrderStatusChangeAuditEvent({
      tx, db, orderId: doc.orderId, organizationId: doc.organizationId, branchId: doc.branchId,
      fromStatus, toStatus: "cancelled", actorType: "staff", actorUid: respondedByActorUid, actorRoles: null,
      reasonCode: "operationalIssue", reasonMessage: `Kurye iptal talebi: ${doc.reason}`, now,
    });
    applyCancellationStockHandling(tx, db, stockPlan);
  }
  tx.update(ref, { status: "approved", decidedByUid: respondedByActorUid, decidedAt: now });
  return { newValue: { orderId: doc.orderId, status: "cancelled" } };
}

/** Onay Kutusu → rejected: the delivery goes on; the courier sees why not. */
export async function applyCourierOrderCancellationRejected(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, now, respondedByActorUid } = params;
  const { ref, doc } = await loadPendingCancellation(params);
  tx.update(ref, { status: "rejected", decidedByUid: respondedByActorUid, decidedAt: now });
  tx.set(db.collection("orders").doc(doc.orderId), { courierCancellationStatus: "rejected" }, { merge: true });
  return { newValue: { orderId: doc.orderId, status: "rejected" } };
}

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

/** Active managers of [branchId], and every active admin/owner of the organization. */
export async function resolveCourierSupervisorUids(db: Firestore, organizationId: string, branchId: string): Promise<string[]> {
  const snap = await db.collection("memberships")
    .where("organizationId", "==", organizationId)
    .where("status", "==", "active")
    .get();
  const uids: string[] = [];
  for (const docSnap of snap.docs) {
    const m = docSnap.data();
    const roles: string[] = Array.isArray(m.roles) ? m.roles.filter((r: unknown): r is string => typeof r === "string") : [];
    const branches: unknown[] = Array.isArray(m.branchAccess) ? m.branchAccess : [];
    const orgWide = roles.some((r) => roleHasPermission(r, "manageStaffAccounts"));
    const branchManager = roles.includes("manager") && branches.includes(branchId);
    if ((orgWide || branchManager) && typeof m.uid === "string") uids.push(m.uid);
  }
  return uids;
}

export async function handleCancellationRequestWrite(
  db: Firestore,
  orderId: string,
  before: DocumentData | undefined,
  after: DocumentData | undefined,
) {
  if (!after) return null;
  const request = after as CourierCancellationRequestDoc;
  const key = `courierCancellation-${orderId}-${request.attempt}`;
  if (request.status === "pending" && before?.status !== "pending") {
    const uids = await resolveCourierSupervisorUids(db, request.organizationId, request.branchId);
    return deliverCourierNotification(db, `${key}-requested`, uids, {
      title: "Kurye iptal talebi",
      body: `${request.orderNumber} · ${request.courierName}: ${request.reason}`,
      data: { type: "courierCancellationRequested", orderId, branchId: request.branchId },
    });
  }
  if ((request.status === "approved" || request.status === "rejected") && before?.status === "pending") {
    return deliverCourierNotification(db, `${key}-${request.status}`, [request.courierUid], {
      title: request.status === "approved" ? "İptal talebiniz onaylandı" : "İptal talebiniz reddedildi",
      body: request.status === "approved"
        ? `${request.orderNumber} iptal edildi. Paketi şubeye geri getirin.`
        : `${request.orderNumber}: teslimata devam edin.`,
      data: { type: "courierCancellationDecided", orderId, status: request.status },
    });
  }
  return null;
}

export async function handlePaymentChangeWrite(
  db: Firestore,
  orderId: string,
  before: DocumentData | undefined,
  after: DocumentData | undefined,
) {
  if (!after || before) return null;
  const change = after as CourierPaymentChangeDoc;
  const uids = await resolveCourierSupervisorUids(db, change.organizationId, change.branchId);
  return deliverCourierNotification(db, `courierPaymentChange-${orderId}`, uids, {
    title: "Ödeme yöntemi değişti",
    body: `${change.orderNumber} · ${change.courierName}: ${methodLabel(change.fromMethodId)} → ${methodLabel(change.toMethodId)}`,
    data: { type: "courierPaymentChanged", orderId, branchId: change.branchId },
  });
}

export const onCourierCancellationRequestWrittenNotify = onDocumentWritten(
  `${COURIER_CANCELLATION_REQUESTS_COLLECTION}/{orderId}`,
  async (event) => {
    await handleCancellationRequestWrite(getFirestore(), event.params.orderId, event.data?.before?.data(), event.data?.after?.data());
  },
);

export const onCourierPaymentChangeWrittenNotify = onDocumentWritten(
  `${COURIER_PAYMENT_CHANGES_COLLECTION}/{orderId}`,
  async (event) => {
    await handlePaymentChangeWrite(getFirestore(), event.params.orderId, event.data?.before?.data(), event.data?.after?.data());
  },
);
