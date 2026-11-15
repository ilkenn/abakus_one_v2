import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { onDocumentCreated } from "firebase-functions/v2/firestore";
import { getFirestore, Timestamp, type DocumentData, type Firestore, type Transaction } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { requireStaffPermission, roleHasPermission } from "./staffAuthorization";
import { holdsPermission } from "./staffScope";
import { deliverCourierNotification } from "./courierNotifications";

/**
 * ADR-085 stage 6C-2 (product owner approved 2026-11-15) — the manager's
 * authority and the "zero hidden action" shield.
 *
 * - **A written reason** of at least [MIN_STAFF_REASON_LENGTH] characters
 *   for every staff cancellation (delivery, takeaway, reservation
 *   pre-order, dine-in order and dine-in line) and every comp/discount
 *   ([requireStaffReason]).
 * - **The manager acts at once, but never unseen.** A branch manager's own
 *   comp/discount, accepted-line cancellation, order cancellation and cash
 *   count with a difference apply immediately — and each one writes an
 *   `oversightAlerts` record, pushed to every admin/owner only
 *   ([recordManagerAction]). An admin/owner's own action is not alerted
 *   (they are the audience); it still has its audit event. Staff requests
 *   keep going to manager approval.
 * - Alerts are server-written (rules default-deny), never deleted; an
 *   admin/owner can only mark one "Görüldü" ([acknowledgeOversightAlert]).
 */
export const OVERSIGHT_ALERTS_COLLECTION = "oversightAlerts";
export const MIN_STAFF_REASON_LENGTH = 5;
const MAX_STAFF_REASON_LENGTH = 500;
const LIST_LIMIT = 200;

export type OversightAlertType =
  | "managerComp"
  | "managerLineCancellation"
  | "managerOrderCancellation"
  | "managerCashVariance";

export interface OversightAlertDoc {
  organizationId: string;
  branchId: string;
  type: OversightAlertType;
  actorUid: string;
  actorName: string | null;
  targetRef: string;
  orderId: string | null;
  orderNumber: string | null;
  amountMinorUnits: number | null;
  /** For a comp/discount: its kind (`complimentary`/`percentage`/`fixedAmount`); for a cash count: `over`/`short`. */
  detail: string | null;
  reason: string;
  createdAt: Timestamp;
  acknowledgedAt: Timestamp | null;
  acknowledgedByUid: string | null;
}

/** The trimmed written reason, [MIN_STAFF_REASON_LENGTH]–500 characters; `reason/too-short` otherwise. */
export function requireStaffReason(raw: unknown, field = "reasonMessage"): string {
  const trimmed = typeof raw === "string" ? raw.trim() : "";
  if (trimmed.length < MIN_STAFF_REASON_LENGTH) {
    throw new HttpsError(
      "invalid-argument",
      `${field} must be at least ${MIN_STAFF_REASON_LENGTH} characters.`,
      { code: "reason/too-short" },
    );
  }
  if (trimmed.length > MAX_STAFF_REASON_LENGTH) {
    throw new HttpsError("invalid-argument", `${field} is too long.`, { code: "reason/too-long" });
  }
  return trimmed;
}

/** The caller as an oversight actor — `alert` is false for an admin/owner (organization-wide authority). */
export interface OversightActor {
  uid: string;
  name: string | null;
  alert: boolean;
}

export async function oversightActorOf(request: CallableRequest, organizationId: string): Promise<OversightActor> {
  const orgWide = await holdsPermission(request, organizationId, "manageStaffAccounts");
  const token = (request.auth?.token ?? {}) as Record<string, unknown>;
  const name = typeof token.name === "string" && token.name.trim().length > 0 ? token.name.trim() : null;
  return { uid: request.auth!.uid, name, alert: !orgWide };
}

/**
 * Writes the manager-action alert inside the caller's transaction (after
 * its reads). Deterministic id, so a retried transaction never doubles it.
 * Nothing is written for an admin/owner.
 */
export function recordManagerAction(tx: Transaction, db: Firestore, actor: OversightActor, params: {
  alertId: string;
  organizationId: string;
  branchId: string;
  type: OversightAlertType;
  targetRef: string;
  orderId?: string | null;
  orderNumber?: string | null;
  amountMinorUnits?: number | null;
  detail?: string | null;
  reason: string;
  now: Timestamp;
}): void {
  if (!actor.alert) return;
  const doc: OversightAlertDoc = {
    organizationId: params.organizationId,
    branchId: params.branchId,
    type: params.type,
    actorUid: actor.uid,
    actorName: actor.name,
    targetRef: params.targetRef,
    orderId: params.orderId ?? null,
    orderNumber: params.orderNumber ?? null,
    amountMinorUnits: params.amountMinorUnits ?? null,
    detail: params.detail ?? null,
    reason: params.reason,
    createdAt: params.now,
    acknowledgedAt: null,
    acknowledgedByUid: null,
  };
  tx.set(db.collection(OVERSIGHT_ALERTS_COLLECTION).doc(params.alertId), doc);
}

export function orderNumberOf(order: DocumentData): string | null {
  return typeof order.orderNumber === "string" && order.orderNumber.length > 0 ? order.orderNumber : null;
}

/** The order's grand total (minor units), `null` when it carries no pricing. */
export function orderTotalMinorUnitsOf(order: DocumentData): number | null {
  const total = order.pricing?.grandTotal?.minorUnits;
  return typeof total === "number" ? total : null;
}

/** Every active admin/owner of the organization (members whose role holds `manageStaffAccounts`). */
export async function resolveOrgOverseerUids(db: Firestore, organizationId: string): Promise<string[]> {
  const snap = await db.collection("memberships")
    .where("organizationId", "==", organizationId)
    .where("status", "==", "active")
    .get();
  const uids: string[] = [];
  for (const docSnap of snap.docs) {
    const m = docSnap.data();
    const roles: string[] = Array.isArray(m.roles) ? m.roles.filter((r: unknown): r is string => typeof r === "string") : [];
    if (roles.some((r) => roleHasPermission(r, "manageStaffAccounts")) && typeof m.uid === "string") uids.push(m.uid);
  }
  return uids;
}

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.length === 0) throw new HttpsError("invalid-argument", `${field} is required.`);
  return raw;
}

function serializeAlert(id: string, alert: OversightAlertDoc) {
  return {
    alertId: id,
    branchId: alert.branchId,
    type: alert.type,
    actorName: alert.actorName,
    orderId: alert.orderId,
    orderNumber: alert.orderNumber,
    amountMinorUnits: alert.amountMinorUnits,
    detail: alert.detail,
    reason: alert.reason,
    createdAtMillis: alert.createdAt.toMillis(),
    acknowledged: alert.acknowledgedAt != null,
  };
}

/** "Müdür İşlemleri" (admin/owner only): the latest manager actions, newest first. */
export const listOversightAlerts = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  await requireStaffPermission(request, organizationId, "manageStaffAccounts");
  const snap = await getFirestore().collection(OVERSIGHT_ALERTS_COLLECTION)
    .where("organizationId", "==", organizationId)
    .orderBy("createdAt", "desc")
    .limit(LIST_LIMIT)
    .get();
  return { organizationId, alerts: snap.docs.map((d) => serializeAlert(d.id, d.data() as OversightAlertDoc)) };
});

/** Marks one alert "Görüldü". The record itself never changes otherwise. */
export const acknowledgeOversightAlert = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const alertId = requireString(data.alertId, "alertId");
  await requireStaffPermission(request, organizationId, "manageStaffAccounts");
  const db = getFirestore();
  const ref = db.collection(OVERSIGHT_ALERTS_COLLECTION).doc(alertId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists || snap.data()!.organizationId !== organizationId) throw new HttpsError("not-found", "Alert not found.");
    if (snap.data()!.acknowledgedAt) return { alertId, duplicate: true };
    tx.update(ref, { acknowledgedAt: Timestamp.now(), acknowledgedByUid: request.auth!.uid });
    return { alertId, duplicate: false };
  });
});

function money(minor: number | null): string {
  if (minor == null) return "";
  const lira = minor / 100;
  return `${lira.toLocaleString("tr-TR", { minimumFractionDigits: 0, maximumFractionDigits: 2 })} TL`;
}

export function oversightMessage(alert: OversightAlertDoc): { title: string; body: string } {
  const who = alert.actorName ?? "Müdür";
  switch (alert.type) {
    case "managerComp":
      return {
        title: "Müdür ikram/indirim yaptı",
        body: `${who}: ${money(alert.amountMinorUnits)} — ${alert.reason}`,
      };
    case "managerLineCancellation":
      return {
        title: "Müdür ürün iptal etti",
        body: `${who}: ${alert.orderNumber ?? ""} — ${alert.reason}`,
      };
    case "managerOrderCancellation":
      return {
        title: "Müdür sipariş iptal etti",
        body: `${who}: ${alert.orderNumber ?? ""} ${money(alert.amountMinorUnits)} — ${alert.reason}`,
      };
    case "managerCashVariance":
      return {
        title: alert.detail === "short" ? "Kasa açığı kabul edildi" : "Kasa fazlası kabul edildi",
        body: `${who}: ${money(alert.amountMinorUnits)} — ${alert.reason}`,
      };
  }
}

export async function handleOversightAlertCreated(db: Firestore, alertId: string, created: DocumentData | undefined) {
  if (!created) return null;
  const alert = created as OversightAlertDoc;
  const uids = await resolveOrgOverseerUids(db, alert.organizationId);
  const message = oversightMessage(alert);
  return deliverCourierNotification(db, `oversight-${alertId}`, uids, {
    ...message,
    data: { type: alert.type, alertId, branchId: alert.branchId, orderId: alert.orderId ?? "" },
  });
}

export const onOversightAlertCreatedNotify = onDocumentCreated(
  `${OVERSIGHT_ALERTS_COLLECTION}/{alertId}`,
  async (event) => {
    await handleOversightAlertCreated(getFirestore(), event.params.alertId, event.data?.data());
  },
);
