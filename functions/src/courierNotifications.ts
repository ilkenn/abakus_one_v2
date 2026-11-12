import { onDocumentWritten } from "firebase-functions/v2/firestore";
import { getFirestore, type DocumentData, type Firestore } from "firebase-admin/firestore";
import { getMessaging } from "firebase-admin/messaging";
import * as logger from "firebase-functions/logger";
import { roleHasPermission } from "./staffAuthorization";
import { COURIER_ASSIGNED_ORDERS_COLLECTION, COURIER_POOL_REQUESTS_COLLECTION } from "./courierPool";

/**
 * 2026-11-12 (Faz 3c) — push notifications (FCM) for the courier pool
 * (ADR-078):
 *
 * - **Staff** — a new external-courier request ("Talep Oluştur") notifies
 *   every active member of the organization holding
 *   `approveCourierPoolRequests` with access to the package's branch
 *   (Kasiyer, Mutfak Paket Yetkilisi, Müdür, Admin, İşletme Sahibi). The
 *   Windows POS has no FCM; it keeps its live badge and alert sound.
 * - **Courier** — a package assigned or reserved to it (pool approval or a
 *   direct staff assignment), and, for information, its request rejected,
 *   given to another courier, withdrawn from the pool or the order closed.
 *
 * Recipients are resolved server-side only (memberships / the courier's
 * linked `authUid`), never from anything a client sent. Each notification
 * is sent at most once (`courierNotificationDeliveries/{key}` is created
 * first; a retried trigger finds it and stops). Tokens FCM reports as
 * permanently invalid are revoked, like the reservation notifications. In
 * the emulator nothing is sent to Google — the recipients and the content
 * are still resolved and recorded, which is what the tests check.
 */

export const COURIER_NOTIFICATION_DELIVERIES_COLLECTION = "courierNotificationDeliveries";
/** Android notification channel the app creates (`flutter_local_notifications`). */
export const COURIER_ALERTS_CHANNEL_ID = "courier_alerts";

export type CourierNotificationType =
  | "courierPoolRequest"
  | "courierAssigned"
  | "courierReserved"
  | "courierRequestRejected";

export interface CourierPushMessage {
  title: string;
  body: string;
  data: Record<string, string>;
}

export interface CourierPushResult {
  successCount: number;
  invalidTokens: string[];
}

export type CourierPushSender = (tokens: string[], message: CourierPushMessage) => Promise<CourierPushResult>;

async function realSender(tokens: string[], message: CourierPushMessage): Promise<CourierPushResult> {
  if (tokens.length === 0) return { successCount: 0, invalidTokens: [] };
  const response = await getMessaging().sendEachForMulticast({
    tokens,
    notification: { title: message.title, body: message.body },
    data: message.data,
    android: {
      priority: "high",
      notification: { channelId: COURIER_ALERTS_CHANNEL_ID, sound: "default" },
    },
    apns: { payload: { aps: { sound: "default" } } },
  });
  const invalidTokens: string[] = [];
  response.responses.forEach((r, i) => {
    const code = r.error?.code;
    if (
      !r.success &&
      (code === "messaging/registration-token-not-registered" ||
        code === "messaging/invalid-registration-token" ||
        code === "messaging/invalid-argument")
    ) {
      invalidTokens.push(tokens[i]);
    }
  });
  return { successCount: response.successCount, invalidTokens };
}

function isEmulatorContext(): boolean {
  return Boolean(process.env.FIRESTORE_EMULATOR_HOST || process.env.FUNCTIONS_EMULATOR);
}

const emulatorSender: CourierPushSender = async (tokens) => {
  logger.info(`[courierNotifications] emulator — not calling FCM (${tokens.length} token(s)).`);
  return { successCount: tokens.length, invalidTokens: [] };
};

export function defaultCourierPushSender(): CourierPushSender {
  return isEmulatorContext() ? emulatorSender : realSender;
}

function amountText(minorUnits: unknown): string {
  const value = typeof minorUnits === "number" ? minorUnits : 0;
  const whole = Math.trunc(value / 100);
  const cents = value % 100;
  return cents === 0 ? `${whole} TL` : `${whole},${String(cents).padStart(2, "0")} TL`;
}

/** Staff: a new pool request. Pure, so the copy is unit-testable. */
export function poolRequestMessage(requestId: string, request: DocumentData): CourierPushMessage {
  return {
    title: "Yeni kurye talebi",
    body: `${request.courierName ?? "Dış kurye"} · ${request.orderNumber ?? ""} (${request.neighborhoodName ?? ""}) · ${amountText(request.amountDueMinorUnits)}`,
    data: {
      type: "courierPoolRequest",
      requestId,
      orderId: String(request.orderId ?? ""),
      branchId: String(request.branchId ?? ""),
    },
  };
}

/** Courier: a package assigned or reserved to it. */
export function assignmentMessage(orderId: string, projection: DocumentData): CourierPushMessage {
  const reserved = projection.status === "reserved";
  const where = [projection.neighborhoodName, projection.branchName ? `Alış: ${projection.branchName}` : null]
    .filter((p) => typeof p === "string" && p.length > 0)
    .join(" · ");
  return {
    title: reserved ? "Paket size ayrıldı" : "Yeni teslimat",
    body: `${projection.orderNumber ?? orderId}${where ? ` — ${where}` : ""}${reserved ? " (mutfakta hazırlanıyor)" : ""}`,
    data: { type: reserved ? "courierReserved" : "courierAssigned", orderId },
  };
}

/** Courier: its request did not get the package (information only). */
export function requestRejectedMessage(requestId: string, request: DocumentData): CourierPushMessage {
  const reason = (() => {
    switch (request.rejection) {
      case "otherApproved": return "başka bir kuryeye verildi";
      case "withdrawn": return "havuzdan geri alındı";
      case "orderClosed": return "sipariş kapandı";
      default: return "talebiniz reddedildi";
    }
  })();
  return {
    title: "Havuz talebi sonuçlandı",
    body: `${request.orderNumber ?? ""} (${request.neighborhoodName ?? ""}): ${reason}.`,
    data: { type: "courierRequestRejected", requestId, orderId: String(request.orderId ?? "") },
  };
}

/** Active members of [organizationId] who may approve pool requests at [branchId]. */
export async function resolvePoolApproverUids(db: Firestore, organizationId: string, branchId: string): Promise<string[]> {
  const snap = await db.collection("memberships")
    .where("organizationId", "==", organizationId)
    .where("status", "==", "active")
    .get();
  const uids: string[] = [];
  for (const doc of snap.docs) {
    const m = doc.data();
    const roles: unknown[] = Array.isArray(m.roles) ? m.roles : [];
    const branches: unknown[] = Array.isArray(m.branchAccess) ? m.branchAccess : [];
    const canApprove = roles.some((r) => typeof r === "string" && roleHasPermission(r, "approveCourierPoolRequests"));
    if (canApprove && branches.includes(branchId) && typeof m.uid === "string") uids.push(m.uid);
  }
  return uids;
}

async function activeTokensFor(db: Firestore, uids: string[]) {
  const docs: FirebaseFirestore.QueryDocumentSnapshot[] = [];
  for (let i = 0; i < uids.length; i += 30) {
    const chunk = uids.slice(i, i + 30);
    const snap = await db.collection("deviceTokens").where("uid", "in", chunk).where("revokedAt", "==", null).get();
    docs.push(...snap.docs);
  }
  return docs.filter((d) => typeof d.data().token === "string" && d.data().token.length > 0);
}

export interface DeliverResult {
  status: "sent" | "duplicate" | "no-recipients" | "no-tokens" | "failed";
  recipientUids: string[];
  tokenCount: number;
}

/**
 * Sends [message] once (per [key]) to every active device of [uids], and
 * records the outcome in `courierNotificationDeliveries/{key}`.
 */
export async function deliverCourierNotification(
  db: Firestore,
  key: string,
  uids: string[],
  message: CourierPushMessage,
  sender: CourierPushSender = defaultCourierPushSender(),
): Promise<DeliverResult> {
  const ref = db.collection(COURIER_NOTIFICATION_DELIVERIES_COLLECTION).doc(key);
  const unique = [...new Set(uids)];
  const now = new Date().toISOString();
  try {
    await ref.create({ type: message.data.type, recipientUids: unique, title: message.title, body: message.body, data: message.data, status: "pending", createdAt: now });
  } catch {
    return { status: "duplicate", recipientUids: unique, tokenCount: 0 };
  }
  if (unique.length === 0) {
    await ref.update({ status: "no-recipients", updatedAt: now });
    return { status: "no-recipients", recipientUids: unique, tokenCount: 0 };
  }
  const tokenDocs = await activeTokensFor(db, unique);
  if (tokenDocs.length === 0) {
    await ref.update({ status: "no-tokens", updatedAt: now });
    return { status: "no-tokens", recipientUids: unique, tokenCount: 0 };
  }
  const tokens = tokenDocs.map((d) => d.data().token as string);
  try {
    const result = await sender(tokens, message);
    const invalid = new Set(result.invalidTokens);
    await Promise.all(
      tokenDocs.filter((d) => invalid.has(d.data().token)).map((d) => d.ref.set({ revokedAt: now, updatedAt: now }, { merge: true })),
    );
    await ref.update({ status: "sent", tokenCount: tokens.length, successCount: result.successCount, invalidTokenCount: invalid.size, updatedAt: now });
    return { status: "sent", recipientUids: unique, tokenCount: tokens.length };
  } catch (error) {
    logger.error("[courierNotifications] send failed", { key, error: String(error) });
    await ref.update({ status: "failed", updatedAt: now });
    return { status: "failed", recipientUids: unique, tokenCount: tokens.length };
  }
}

function millis(value: unknown): number {
  const v = value as { toMillis?: () => number } | null | undefined;
  return typeof v?.toMillis === "function" ? v.toMillis() : 0;
}

/** Staff on a new pending request; the courier when its request is rejected. */
export async function handlePoolRequestWrite(
  db: Firestore,
  requestId: string,
  before: DocumentData | undefined,
  after: DocumentData | undefined,
  sender?: CourierPushSender,
): Promise<DeliverResult | null> {
  if (!after) return null;
  if (after.status === "pending" && before?.status !== "pending") {
    const uids = await resolvePoolApproverUids(db, after.organizationId, after.branchId);
    return deliverCourierNotification(db, `poolRequest-${requestId}-${millis(after.createdAt)}`, uids, poolRequestMessage(requestId, after), sender);
  }
  if (after.status === "rejected" && before?.status === "pending" && typeof after.courierAuthUid === "string") {
    return deliverCourierNotification(
      db, `poolRequestRejected-${requestId}-${millis(after.createdAt)}`, [after.courierAuthUid],
      requestRejectedMessage(requestId, after), sender,
    );
  }
  return null;
}

/** The courier when an order newly lands on its own copy (assigned or reserved). */
export async function handleAssignedOrderWrite(
  db: Firestore,
  orderId: string,
  before: DocumentData | undefined,
  after: DocumentData | undefined,
  sender?: CourierPushSender,
): Promise<DeliverResult | null> {
  if (!after || typeof after.courierAuthUid !== "string" || after.courierAuthUid.length === 0) return null;
  const newCourier = before?.courierId !== after.courierId || before?.courierAuthUid !== after.courierAuthUid;
  const nowAssigned = before?.status === "reserved" && after.status === "assigned";
  if (!newCourier && !nowAssigned) return null;
  return deliverCourierNotification(
    db, `courierOrder-${orderId}-${after.courierId}-${after.status === "reserved" ? "reserved" : "assigned"}`,
    [after.courierAuthUid], assignmentMessage(orderId, after), sender,
  );
}

export const onCourierPoolRequestWrittenNotify = onDocumentWritten(
  `${COURIER_POOL_REQUESTS_COLLECTION}/{requestId}`,
  async (event) => {
    await handlePoolRequestWrite(getFirestore(), event.params.requestId, event.data?.before?.data(), event.data?.after?.data());
  },
);

export const onCourierAssignedOrderWrittenNotify = onDocumentWritten(
  `${COURIER_ASSIGNED_ORDERS_COLLECTION}/{orderId}`,
  async (event) => {
    await handleAssignedOrderWrite(getFirestore(), event.params.orderId, event.data?.before?.data(), event.data?.after?.data());
  },
);
