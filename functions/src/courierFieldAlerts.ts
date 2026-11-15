import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { getFirestore, Timestamp, type DocumentData, type Firestore, type Transaction } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId } from "./correlationId";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { holdsPermission } from "./staffScope";
import { deliverCourierNotification, resolvePoolApproverUids } from "./courierNotifications";
import { actorRolesFor } from "./courierPool";
import { resolveCourierSupervisorUids } from "./courierDeliveryControls";
import { orderAmountDueMinorUnits } from "./courierSettlement";

/**
 * ADR-085 stage 6C-1 (product owner approved 2026-11-15) — safety in the
 * field.
 *
 * - **Branch settings** (`branches/{id}.courierOperationSettings`): the
 *   courier cash limit (default 3.000 TL) and the late-delivery threshold
 *   (default 35 minutes), set by a manager of the branch or an admin/owner.
 * - **Cash limit**: "Teslim Ettim" with cash adds the amount to the
 *   courier's carried cash (`couriers/{id}.carriedCashMinorUnits`, mirrored
 *   to `courierAccounts/{uid}` for the courier app); above the limit the
 *   courier sees "Nakit limitiniz doldu, kasaya teslim yapın" and an alert
 *   opens. The cashier's settlement resets it and closes the alert.
 * - **Late delivery**: every 5 minutes [sweepLateCourierDeliveries] marks
 *   an order still out for delivery past the threshold (from "Yola Çıktım",
 *   else from the hand-over to the courier) and opens an alert; the courier
 *   app also turns the card red by itself from the same numbers.
 * - **Alerts** (`operationalAlerts`, server-written): pushed to the
 *   branch's cashiers, packing leads and managers and to every
 *   admin/owner, and listed in the panel's "Kurye Uyarıları" (the Windows
 *   POS has no push).
 * - **Pool hand-over** ("Teslim Et", [confirmPackageHandover]): a pool
 *   courier who got a ready package at approval collects it at the counter;
 *   until the staff ticks "Eksiksiz Hazırlandı" there, the courier cannot
 *   press "Yola Çıktım".
 */
export const OPERATIONAL_ALERTS_COLLECTION = "operationalAlerts";

export const DEFAULT_COURIER_CASH_LIMIT_MINOR_UNITS = 300_000; // 3.000 TL
export const DEFAULT_LATE_DELIVERY_MINUTES = 35;
const MAX_CASH_LIMIT_MINOR_UNITS = 100_000_000;
const MIN_LATE_MINUTES = 5;
const MAX_LATE_MINUTES = 240;

export type OperationalAlertType = "courierCashLimit" | "courierLate";

export interface OperationalAlertDoc {
  organizationId: string;
  branchId: string;
  type: OperationalAlertType;
  status: "open" | "resolved";
  courierId: string;
  courierUid: string | null;
  courierName: string;
  orderId: string | null;
  orderNumber: string | null;
  amountMinorUnits: number | null;
  limitMinorUnits: number | null;
  minutes: number | null;
  openedAt: Timestamp;
  resolvedAt: Timestamp | null;
}

export interface CourierOperationSettings {
  cashLimitMinorUnits: number;
  lateDeliveryMinutes: number;
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

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

export function courierOperationSettingsOf(branch: DocumentData | undefined): CourierOperationSettings {
  const raw = (branch?.courierOperationSettings ?? {}) as Record<string, unknown>;
  const cash = raw.cashLimitMinorUnits;
  const late = raw.lateDeliveryMinutes;
  return {
    cashLimitMinorUnits: typeof cash === "number" && Number.isInteger(cash) && cash > 0 ? cash : DEFAULT_COURIER_CASH_LIMIT_MINOR_UNITS,
    lateDeliveryMinutes: typeof late === "number" && Number.isInteger(late) && late >= MIN_LATE_MINUTES ? late : DEFAULT_LATE_DELIVERY_MINUTES,
  };
}

/** When the delivery clock started: "Yola Çıktım", else the hand-over (`outForDelivery`). */
export function deliveryClockStartMillis(order: DocumentData): number | null {
  const departed = order.departedAt as { toMillis?: () => number } | undefined;
  if (departed && typeof departed.toMillis === "function") return departed.toMillis();
  const history: unknown[] = Array.isArray(order.statusHistory) ? order.statusHistory : [];
  for (let i = history.length - 1; i >= 0; i--) {
    const entry = history[i] as Record<string, unknown>;
    if (entry?.newValue === "outForDelivery" && typeof entry.timestamp === "string") {
      const millis = Date.parse(entry.timestamp);
      return Number.isNaN(millis) ? null : millis;
    }
  }
  return null;
}

/** Minutes past the threshold, or `null` while still on time (or not started / already delivered). */
export function lateMinutes(order: DocumentData, settings: CourierOperationSettings, nowMillis: number): number | null {
  if (order.channel !== "delivery" || order.status !== "outForDelivery" || order.courierReportedDeliveredAt) return null;
  const start = deliveryClockStartMillis(order);
  if (start === null) return null;
  const elapsed = Math.floor((nowMillis - start) / 60_000);
  return elapsed >= settings.lateDeliveryMinutes ? elapsed : null;
}

// ---------------------------------------------------------------------------
// Alerts (written by other modules inside their transactions)
// ---------------------------------------------------------------------------

export function cashLimitAlertRef(db: Firestore, courierId: string) {
  return db.collection(OPERATIONAL_ALERTS_COLLECTION).doc(`cashLimit-${courierId}`);
}

export function lateAlertRef(db: Firestore, orderId: string) {
  return db.collection(OPERATIONAL_ALERTS_COLLECTION).doc(`late-${orderId}`);
}

/** Opens (or re-opens) the courier's cash-limit alert. */
export function openCashLimitAlert(tx: Transaction, db: Firestore, params: {
  organizationId: string; branchId: string; courierId: string; courierUid: string | null; courierName: string;
  carriedMinorUnits: number; limitMinorUnits: number; now: Timestamp;
}): void {
  const alert: OperationalAlertDoc = {
    organizationId: params.organizationId, branchId: params.branchId, type: "courierCashLimit", status: "open",
    courierId: params.courierId, courierUid: params.courierUid, courierName: params.courierName,
    orderId: null, orderNumber: null, amountMinorUnits: params.carriedMinorUnits, limitMinorUnits: params.limitMinorUnits,
    minutes: null, openedAt: params.now, resolvedAt: null,
  };
  tx.set(cashLimitAlertRef(db, params.courierId), alert);
}

export function resolveAlert(tx: Transaction, ref: FirebaseFirestore.DocumentReference, now: Timestamp): void {
  tx.set(ref, { status: "resolved", resolvedAt: now }, { merge: true });
}

/**
 * "Teslim Ettim" with cash: adds the amount to what the courier carries,
 * opens the cash-limit alert the first time the limit is passed, and
 * mirrors the state to the courier's own account for the app. Call after
 * every read of the transaction.
 */
export function applyCarriedCash(tx: Transaction, db: Firestore, params: {
  organizationId: string; branchId: string; courierRef: FirebaseFirestore.DocumentReference; courier: DocumentData;
  courierUid: string; order: DocumentData; settings: CourierOperationSettings; now: Timestamp;
}): { carriedMinorUnits: number; exceeded: boolean } {
  const before = Number(params.courier.carriedCashMinorUnits ?? 0);
  const carried = before + orderAmountDueMinorUnits(params.order);
  const limit = params.settings.cashLimitMinorUnits;
  const exceeded = carried > limit;
  const firstTime = exceeded && !params.courier.cashLimitExceededAt;
  tx.set(params.courierRef, {
    carriedCashMinorUnits: carried,
    ...(firstTime ? { cashLimitExceededAt: params.now } : {}),
  }, { merge: true });
  tx.set(db.collection("courierAccounts").doc(params.courierUid), {
    carriedCashMinorUnits: carried, cashLimitMinorUnits: limit, cashLimitExceeded: exceeded,
  }, { merge: true });
  if (firstTime) {
    openCashLimitAlert(tx, db, {
      organizationId: params.organizationId, branchId: params.branchId, courierId: params.courierRef.id,
      courierUid: params.courierUid, courierName: String(params.courier.displayName ?? ""),
      carriedMinorUnits: carried, limitMinorUnits: limit, now: params.now,
    });
  }
  return { carriedMinorUnits: carried, exceeded };
}

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

async function loadBranch(organizationId: string, branchId: string) {
  const snap = await getFirestore().collection("branches").doc(branchId).get();
  if (!snap.exists || snap.data()!.organizationId !== organizationId) throw new HttpsError("not-found", "Branch not found.");
  return snap;
}

export const getBranchCourierSettings = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const branchId = requireString(data.branchId, "branchId");
  await requireStaffPermission(request, organizationId, "approveCourierPoolRequests");
  if (!(await holdsPermission(request, organizationId, "manageStaffAccounts"))) {
    await requireBranchAccess(request, organizationId, branchId);
  }
  const branch = await loadBranch(organizationId, branchId);
  return { organizationId, branchId, ...courierOperationSettingsOf(branch.data()) };
});

/** A manager of the branch or an admin/owner sets the cash limit and the late threshold. */
export const setBranchCourierSettings = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const branchId = requireString(data.branchId, "branchId");
  const cash = data.cashLimitMinorUnits;
  const late = data.lateDeliveryMinutes;
  if (typeof cash !== "number" || !Number.isInteger(cash) || cash <= 0 || cash > MAX_CASH_LIMIT_MINOR_UNITS) {
    invalid("cashLimitMinorUnits must be a positive whole number of kuruş.", "courierSettings/invalid-cash-limit");
  }
  if (typeof late !== "number" || !Number.isInteger(late) || late < MIN_LATE_MINUTES || late > MAX_LATE_MINUTES) {
    invalid(`lateDeliveryMinutes must be ${MIN_LATE_MINUTES}–${MAX_LATE_MINUTES}.`, "courierSettings/invalid-late-minutes");
  }
  await requireStaffPermission(request, organizationId, "manageBranch");
  if (!(await holdsPermission(request, organizationId, "manageStaffAccounts"))) {
    await requireBranchAccess(request, organizationId, branchId);
  }
  const branchSnap = await loadBranch(organizationId, branchId);
  const previous = courierOperationSettingsOf(branchSnap.data());
  const next: CourierOperationSettings = { cashLimitMinorUnits: cash as number, lateDeliveryMinutes: late as number };
  const db = getFirestore();
  await db.runTransaction(async (tx) => {
    const now = Timestamp.now();
    tx.set(branchSnap.ref, { courierOperationSettings: next }, { merge: true });
    writeAuditEvent({
      tx, db, eventId: `courierSettings-${branchId}-${now.toMillis()}`, organizationId, branchId,
      type: "branch.courierSettingsSet", targetRef: branchSnap.ref.path,
      previousValue: { ...previous }, newValue: { ...next },
      actorType: "staff", actorUid: request.auth!.uid, actorRoles: actorRolesFor(request, organizationId),
      correlationId: generateCorrelationId(), now,
    });
  });
  return { organizationId, branchId, ...next };
});

// ---------------------------------------------------------------------------
// Late deliveries
// ---------------------------------------------------------------------------

/** Marks late orders and opens their alerts. Returns how many were newly marked. */
export async function markLateDeliveries(db: Firestore, nowMillis: number): Promise<number> {
  const snap = await db.collection("orders").where("channel", "==", "delivery").where("status", "==", "outForDelivery").get();
  const settingsByBranch = new Map<string, CourierOperationSettings>();
  let marked = 0;
  for (const doc of snap.docs) {
    const order = doc.data();
    if (order.courierLateAt || order.courierReportedDeliveredAt || !order.assignedCourierId) continue;
    const branchId = String(order.branchId ?? "");
    let settings = settingsByBranch.get(branchId);
    if (!settings) {
      settings = courierOperationSettingsOf((await db.collection("branches").doc(branchId).get()).data());
      settingsByBranch.set(branchId, settings);
    }
    const minutes = lateMinutes(order, settings, nowMillis);
    if (minutes === null) continue;
    await db.runTransaction(async (tx) => {
      const fresh = (await tx.get(doc.ref)).data();
      if (!fresh || fresh.courierLateAt || fresh.status !== "outForDelivery" || fresh.courierReportedDeliveredAt) return;
      const courierSnap = await tx.get(db.collection("couriers").doc(String(fresh.assignedCourierId)));
      const courier = courierSnap.data() ?? {};
      const now = Timestamp.fromMillis(nowMillis);
      tx.set(doc.ref, { courierLateAt: now }, { merge: true });
      const alert: OperationalAlertDoc = {
        organizationId: String(fresh.organizationId), branchId, type: "courierLate", status: "open",
        courierId: String(fresh.assignedCourierId), courierUid: (courier.authUid as string | undefined) ?? null,
        courierName: String(courier.displayName ?? ""), orderId: doc.id, orderNumber: String(fresh.orderNumber ?? doc.id),
        amountMinorUnits: null, limitMinorUnits: null, minutes, openedAt: now, resolvedAt: null,
      };
      tx.set(lateAlertRef(db, doc.id), alert);
      marked += 1;
    });
  }
  return marked;
}

export const sweepLateCourierDeliveries = onSchedule({ schedule: "every 5 minutes", timeZone: "Europe/Istanbul" }, async () => {
  await markLateDeliveries(getFirestore(), Date.now());
});

// ---------------------------------------------------------------------------
// Panel list
// ---------------------------------------------------------------------------

function serializeAlert(id: string, alert: OperationalAlertDoc) {
  return {
    alertId: id,
    branchId: alert.branchId,
    type: alert.type,
    courierName: alert.courierName,
    orderId: alert.orderId,
    orderNumber: alert.orderNumber,
    amountMinorUnits: alert.amountMinorUnits,
    limitMinorUnits: alert.limitMinorUnits,
    minutes: alert.minutes,
    openedAtMillis: alert.openedAt.toMillis(),
  };
}

/**
 * "Kurye Uyarıları": open alerts of the caller's branches (an admin/owner:
 * every branch). A late alert whose order has meanwhile been delivered,
 * settled or cancelled is closed here.
 */
export const listOperationalAlerts = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  await requireStaffPermission(request, organizationId, "approveCourierPoolRequests");
  const orgWide = await holdsPermission(request, organizationId, "manageStaffAccounts");
  const byOrg = request.auth.token?.branchAccess as Record<string, unknown> | undefined;
  const own = new Set(Array.isArray(byOrg?.[organizationId]) ? (byOrg![organizationId] as string[]) : []);
  const db = getFirestore();
  const snap = await db.collection(OPERATIONAL_ALERTS_COLLECTION)
    .where("organizationId", "==", organizationId)
    .where("status", "==", "open")
    .get();
  const visible = snap.docs
    .map((doc) => ({ ref: doc.ref, id: doc.id, alert: doc.data() as OperationalAlertDoc }))
    .filter(({ alert }) => orgWide || own.has(alert.branchId));
  const lateOnes = visible.filter(({ alert }) => alert.type === "courierLate" && alert.orderId);
  const orders = lateOnes.length > 0 ? await db.getAll(...lateOnes.map(({ alert }) => db.collection("orders").doc(alert.orderId!))) : [];
  const stale = new Set<string>();
  orders.forEach((orderSnap, i) => {
    const order = orderSnap.data();
    if (!order || order.status !== "outForDelivery" || order.courierReportedDeliveredAt) stale.add(lateOnes[i].id);
  });
  if (stale.size > 0) {
    const batch = db.batch();
    const now = Timestamp.now();
    for (const { ref, id } of visible) if (stale.has(id)) batch.set(ref, { status: "resolved", resolvedAt: now }, { merge: true });
    await batch.commit();
  }
  const alerts = visible
    .filter(({ id }) => !stale.has(id))
    .map(({ id, alert }) => serializeAlert(id, alert))
    .sort((a, b) => b.openedAtMillis - a.openedAtMillis);
  return { organizationId, alerts };
});

// ---------------------------------------------------------------------------
// Pool hand-over ("Teslim Et")
// ---------------------------------------------------------------------------

/** The counter's "Teslim Et" for a pool courier: "Eksiksiz Hazırlandı" is recorded on the order. */
export const confirmPackageHandover = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const orderId = requireString(data.orderId, "orderId");
  if (data.packingVerified !== true) precondition("Tick \"Eksiksiz Hazırlandı\" first.", "courierDispatch/packing-not-verified");
  const db = getFirestore();
  const orderRef = db.collection("orders").doc(orderId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(orderRef);
    if (!snap.exists) throw new HttpsError("not-found", "Order not found.");
    const order = snap.data()!;
    const organizationId = String(order.organizationId);
    const branchId = String(order.branchId);
    await requireStaffPermission(request, organizationId, "manageCourierDispatch");
    await requireBranchAccess(request, organizationId, branchId);
    if (order.channel !== "delivery" || order.status !== "outForDelivery" || !order.assignedCourierId) {
      precondition("The order is not with a courier.", "courierDispatch/not-assigned");
    }
    if (order.packingVerifiedAt) return { orderId, duplicate: true };
    const now = Timestamp.now();
    tx.set(orderRef, { packingVerifiedAt: now, packingVerifiedByUid: request.auth!.uid }, { merge: true });
    writeAuditEvent({
      tx, db, eventId: `packing-${orderId}-verified`, organizationId, branchId,
      type: "courierDispatch.packageHandedOver", targetRef: orderRef.path,
      newValue: { courierId: order.assignedCourierId, packingVerified: true },
      actorType: "staff", actorUid: request.auth!.uid, actorRoles: actorRolesFor(request, organizationId),
      correlationId: generateCorrelationId(), now,
    });
    return { orderId, duplicate: false };
  });
});

// ---------------------------------------------------------------------------
// Notifications
// ---------------------------------------------------------------------------

function alertMessage(alert: OperationalAlertDoc) {
  if (alert.type === "courierCashLimit") {
    const amount = Math.round((alert.amountMinorUnits ?? 0) / 100);
    return {
      staff: { title: "Kurye nakit limiti doldu", body: `${alert.courierName}: ${amount} TL nakit taşıyor — kasaya teslim etmeli.` },
      courier: { title: "Nakit limitiniz doldu", body: "Kasaya teslim yapın." },
    };
  }
  return {
    staff: { title: "Geciken paket", body: `${alert.orderNumber} · ${alert.courierName}: ${alert.minutes} dk oldu, teslim edilmedi.` },
    courier: { title: "Paket gecikti", body: `${alert.orderNumber}: ${alert.minutes} dk oldu.` },
  };
}

export async function handleOperationalAlertWrite(
  db: Firestore,
  alertId: string,
  before: DocumentData | undefined,
  after: DocumentData | undefined,
) {
  if (!after || after.status !== "open" || (before?.status === "open" && millis(before.openedAt) === millis(after.openedAt))) return null;
  const alert = after as OperationalAlertDoc;
  const staff = new Set([
    ...(await resolvePoolApproverUids(db, alert.organizationId, alert.branchId)),
    ...(await resolveCourierSupervisorUids(db, alert.organizationId, alert.branchId)),
  ]);
  const message = alertMessage(alert);
  const key = `alert-${alertId}-${millis(alert.openedAt)}`;
  const data = { type: alert.type, alertId, branchId: alert.branchId, orderId: alert.orderId ?? "" };
  const result = await deliverCourierNotification(db, `${key}-staff`, [...staff], { ...message.staff, data });
  if (alert.courierUid) {
    await deliverCourierNotification(db, `${key}-courier`, [alert.courierUid], { ...message.courier, data });
  }
  return result;
}

function millis(value: unknown): number {
  const v = value as { toMillis?: () => number } | null | undefined;
  return typeof v?.toMillis === "function" ? v.toMillis() : 0;
}

export const onOperationalAlertWrittenNotify = onDocumentWritten(
  `${OPERATIONAL_ALERTS_COLLECTION}/{alertId}`,
  async (event) => {
    await handleOperationalAlertWrite(getFirestore(), event.params.alertId, event.data?.before?.data(), event.data?.after?.data());
  },
);
