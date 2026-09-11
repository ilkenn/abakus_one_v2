import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { requireActiveDeviceSession } from "./trustedDevice";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";
import { isTableGuestSessionActive } from "./tableGuestSessionConfig";

/**
 * Dine-in Sprint 3 — a guest-triggered "someone needs staff attention"
 * signal (waiter call / bill request), distinct from and composing with
 * Dine-in Sprint 1's check-driven `restaurantTables.statusOverride =
 * "billRequested"` (`checkOperations.ts`'s `syncTableBillRequestedOverride`)
 * and Sprint 2's `tableSessionClosure.ts` (which unconditionally clears any
 * override on full table release regardless of which trigger set it).
 *
 * `createServiceRequest` is the one guest-facing callable here — it never
 * requires a trusted-device session (guests don't have one); instead it
 * verifies the caller owns the `tableGuestSessions` document it names,
 * exactly mirroring `submitDineInOrder.ts`'s own `mode: "guestSession"`
 * branch. `resolveServiceRequest` is staff-only, mirroring
 * `tableSessionTransfer.ts`'s own locally-duplicated
 * `authorizeStaffDeviceCommand` shape (this codebase's established
 * per-file helper convention) rather than importing a shared one.
 */

export const SERVICE_REQUESTS_COLLECTION = "serviceRequests";
export type ServiceRequestType = "callWaiter" | "requestBill";
export type ServiceRequestStatus = "pending" | "resolved";

export interface ServiceRequestDoc {
  organizationId: string;
  branchId: string;
  tableId: string;
  tableDisplayName: string;
  tableSessionId: string;
  type: ServiceRequestType;
  status: ServiceRequestStatus;
  createdAt: Timestamp;
  resolvedAt: Timestamp | null;
  resolvedByStaffUid: string | null;
}

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.length === 0) invalid(`${field} is required.`);
  return raw as string;
}
function isServiceRequestType(raw: unknown): raw is ServiceRequestType {
  return raw === "callWaiter" || raw === "requestBill";
}

// -----------------------------------------------------------------------
// createServiceRequest — guest-triggered, ownership-verified, idempotent
// -----------------------------------------------------------------------

export const createServiceRequest = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const guestSessionId = requireNonEmptyString(data.guestSessionId, "guestSessionId");
  if (!isServiceRequestType(data.type)) invalid('type must be "callWaiter" or "requestBill".');
  const type = data.type;
  const uid = request.auth.uid;

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const guestSessionRef = db.collection("tableGuestSessions").doc(guestSessionId);
    const guestSessionSnap = await tx.get(guestSessionRef);
    if (!guestSessionSnap.exists) throw new HttpsError("not-found", "Table guest session not found.");
    const guestSession = guestSessionSnap.data()!;
    if (guestSession.guestAuthUid !== uid) {
      throw new HttpsError("failed-precondition", "This table guest session does not belong to the caller.");
    }
    if (!isTableGuestSessionActive({ status: String(guestSession.status), expiresAt: guestSession.expiresAt })) {
      throw new HttpsError("failed-precondition", "This table guest session is not active.");
    }

    const organizationId = String(guestSession.organizationId);
    const branchId = String(guestSession.branchId);
    const tableId = String(guestSession.tableId);
    const tableSessionId = guestSession.tableSessionId as string | undefined;
    if (!tableSessionId) {
      throw new HttpsError("failed-precondition", "This table guest session has no associated table session — re-scan the QR code.");
    }

    // Idempotent — a second tap of the same button while one is still
    // pending returns the existing request rather than creating a
    // duplicate (also caps guest button-mashing).
    const existingSnap = await tx.get(
      db.collection(SERVICE_REQUESTS_COLLECTION)
        .where("tableSessionId", "==", tableSessionId)
        .where("type", "==", type)
        .where("status", "==", "pending"),
    );
    if (!existingSnap.empty) {
      return { requestId: existingSnap.docs[0].id, alreadyPending: true };
    }

    const tableRef = db.collection("restaurantTables").doc(tableId);
    const tableSnap = await tx.get(tableRef);
    if (!tableSnap.exists) throw new HttpsError("not-found", "Table not found.");
    const tableDisplayName = (tableSnap.data()!.displayName as string | undefined) ?? tableId;

    const now = Timestamp.now();
    const requestRef = db.collection(SERVICE_REQUESTS_COLLECTION).doc();
    const doc: ServiceRequestDoc = {
      organizationId, branchId, tableId, tableDisplayName, tableSessionId,
      type, status: "pending", createdAt: now, resolvedAt: null, resolvedByStaffUid: null,
    };
    tx.set(requestRef, doc);
    if (type === "requestBill") {
      tx.update(tableRef, { statusOverride: "billRequested" });
    }
    return { requestId: requestRef.id, alreadyPending: false };
  });
});

// -----------------------------------------------------------------------
// resolveServiceRequest — staff-only, one tap from the branch overview grid
// -----------------------------------------------------------------------

interface StaffDeviceContext {
  organizationId: string;
  branchId: string;
  uid: string;
}

async function authorizeStaffDeviceCommand(request: CallableRequest, data: Record<string, unknown>): Promise<StaffDeviceContext> {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
  const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");
  requireStaffPermission(request, organizationId, "manageDineInOrders");
  requireBranchAccess(request, organizationId, branchId);
  await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);
  return { organizationId, branchId, uid: request.auth.uid };
}

export const resolveServiceRequest = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeStaffDeviceCommand(request, data);
  const requestId = requireNonEmptyString(data.requestId, "requestId");

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const ref = db.collection(SERVICE_REQUESTS_COLLECTION).doc(requestId);
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Service request not found.");
    const doc = snap.data() as ServiceRequestDoc;
    if (doc.organizationId !== ctx.organizationId || doc.branchId !== ctx.branchId) {
      throw new HttpsError("not-found", "Service request not found.");
    }
    if (doc.status !== "pending") {
      throw new HttpsError("failed-precondition", "Only a pending service request may be resolved.");
    }

    const now = Timestamp.now();
    tx.update(ref, { status: "resolved", resolvedAt: now, resolvedByStaffUid: ctx.uid });
    writeAuditEvent({
      tx, db, eventId: `${ref.path.replace(/\//g, "_")}-resolved-${Date.now()}`,
      organizationId: ctx.organizationId, branchId: ctx.branchId,
      type: "serviceRequest.resolved", targetRef: ref.path,
      newValue: { type: doc.type, tableId: doc.tableId },
      actorType: "staff", actorUid: ctx.uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });
    return { requestId, status: "resolved" };
  });
});
