import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { requireActiveDeviceSession } from "./trustedDevice";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";
import { TABLE_SESSIONS_COLLECTION, GUEST_SUB_ACCOUNTS_COLLECTION } from "./tableSessionConfig";
import { CHECKS_COLLECTION, CHECK_ALLOCATIONS_COLLECTION } from "./checkAllocationConfig";
import { activeReservationTableContextRef, readLiveReservationTableContext } from "./reservationTableContext";

/**
 * AP-3 Wave 2 remainder — physical table transfer/merge (corrected report
 * §6.4/§6.5), distinct from `checkOperations.ts`'s `mergeChecks`/
 * `transferCheckAllocation` (those move MONEY between check documents;
 * these move a whole TABLE SESSION's real-world physical location — reused
 * where the two genuinely overlap, never duplicated: neither function here
 * touches `checkAllocations` money math at all, only the `tableSessionId`
 * foreign key already denormalized onto `checks`/`checkAllocations`).
 *
 * **Safe-transaction-size discipline**: a table session's own document
 * fan-out (guest sessions + sub-accounts + checks + allocations) is
 * realistically small (a handful of documents per physical table) — both
 * commands defensively COUNT everything they're about to move before
 * writing anything, and fail closed with a clear error rather than
 * attempting a partial multi-table-session move if that count ever
 * approaches Firestore's own 500-write transactional limit. A genuine
 * multi-step recoverable operation-aggregate for the pathological case is
 * explicitly out of this pass's scope (disclosed, not silently skipped) —
 * this codebase has no real precedent of a table session this large.
 */

const MAX_SAFE_TRANSACTION_WRITES = 400;

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.length === 0) invalid(`${field} is required.`);
  return raw as string;
}

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

async function loadTable(db: FirebaseFirestore.Firestore, tx: FirebaseFirestore.Transaction, tableId: string, organizationId: string, branchId: string) {
  const ref = db.collection("restaurantTables").doc(tableId);
  const snap = await tx.get(ref);
  if (!snap.exists || snap.data()!.organizationId !== organizationId || snap.data()!.branchId !== branchId) {
    throw new HttpsError("not-found", "Table not found.");
  }
  return { ref, data: snap.data()! };
}

/** Hard reservation-context conflict check shared by transfer and merge — mirrors `openReservationTable`'s own precedent (a DIFFERENT reservation's live context on the target can never be silently overridden). */
async function requireNoForeignReservationConflict(db: FirebaseFirestore.Firestore, tx: FirebaseFirestore.Transaction, tableId: string, now: Date) {
  const liveContext = await readLiveReservationTableContext(activeReservationTableContextRef(db, tableId), now, tx);
  if (liveContext) {
    throw new HttpsError("failed-precondition", "The target table has a live reservation context — cannot move a walk-in table session onto it.", { code: "reservationConflict", reservationId: liveContext.reservationId });
  }
}

// -----------------------------------------------------------------------
// transferTableSession — relocate ONE active session to a currently-free table
// -----------------------------------------------------------------------

export const transferTableSession = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeStaffDeviceCommand(request, data);
  const sourceTableId = requireNonEmptyString(data.sourceTableId, "sourceTableId");
  const targetTableId = requireNonEmptyString(data.targetTableId, "targetTableId");
  if (sourceTableId === targetTableId) invalid("sourceTableId and targetTableId must differ.");

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { ref: sourceRef, data: sourceTable } = await loadTable(db, tx, sourceTableId, ctx.organizationId, ctx.branchId);
    const { ref: targetRef, data: targetTable } = await loadTable(db, tx, targetTableId, ctx.organizationId, ctx.branchId);
    const tableSessionId = (sourceTable.activeTableSessionId as string | null) ?? null;

    // Idempotent replay — the transfer already completed (source cleared,
    // target now points at the same session): report success rather than
    // erroring on a retried call.
    if (!tableSessionId) {
      if (targetTable.activeTableSessionId) {
        return { tableSessionId: targetTable.activeTableSessionId, alreadyTransferred: true };
      }
      throw new HttpsError("failed-precondition", "The source table has no active table session to transfer.");
    }

    if (targetTable.activeTableSessionId && targetTable.activeTableSessionId !== tableSessionId) {
      throw new HttpsError("failed-precondition", "The target table already has a different active session — use mergeTableSessions instead.", { code: "targetSessionConflict" });
    }
    if (targetTable.activeTableSessionId === tableSessionId) {
      return { tableSessionId, alreadyTransferred: true };
    }

    const now = new Date();
    await requireNoForeignReservationConflict(db, tx, targetTableId, now);

    const tableSessionRef = db.collection(TABLE_SESSIONS_COLLECTION).doc(tableSessionId);
    const tableSessionSnap = await tx.get(tableSessionRef);
    if (!tableSessionSnap.exists || tableSessionSnap.data()!.status !== "active") {
      throw new HttpsError("failed-precondition", "The table session is not active.");
    }
    const tableSession = tableSessionSnap.data()!;

    const guestSessionsSnap = await tx.get(db.collection("tableGuestSessions").where("tableSessionId", "==", tableSessionId));
    if (guestSessionsSnap.size > MAX_SAFE_TRANSACTION_WRITES) {
      throw new HttpsError("resource-exhausted", "This table session has too many guest sessions to transfer safely in one transaction.");
    }

    const nowTs = Timestamp.fromDate(now);
    tx.update(tableSessionRef, { tableId: targetTableId, transferredFromTableId: sourceTableId, version: (tableSession.version as number) + 1 });
    for (const doc of guestSessionsSnap.docs) {
      tx.update(doc.ref, { tableId: targetTableId });
    }
    tx.update(sourceRef, { activeTableSessionId: null, status: "cleaning" });
    tx.update(targetRef, { activeTableSessionId: tableSessionId, status: "occupied" });

    writeAuditEvent({
      tx, db, eventId: `${tableSessionRef.path.replace(/\//g, "_")}-transferred-${Date.now()}`,
      organizationId: ctx.organizationId, branchId: ctx.branchId,
      type: "tableSession.transferred", targetRef: tableSessionRef.path,
      newValue: { sourceTableId, targetTableId },
      actorType: "staff", actorUid: ctx.uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now: nowTs,
    });

    return { tableSessionId, alreadyTransferred: false, movedGuestSessionCount: guestSessionsSnap.size };
  });
});

// -----------------------------------------------------------------------
// mergeTableSessions — combine two ALREADY-active sessions into one
// -----------------------------------------------------------------------

export const mergeTableSessions = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeStaffDeviceCommand(request, data);
  const sourceTableId = requireNonEmptyString(data.sourceTableId, "sourceTableId");
  const targetTableId = requireNonEmptyString(data.targetTableId, "targetTableId");
  if (sourceTableId === targetTableId) invalid("sourceTableId and targetTableId must differ.");

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { ref: sourceRef, data: sourceTable } = await loadTable(db, tx, sourceTableId, ctx.organizationId, ctx.branchId);
    const { ref: targetRef, data: targetTable } = await loadTable(db, tx, targetTableId, ctx.organizationId, ctx.branchId);
    const sourceTableSessionId = (sourceTable.activeTableSessionId as string | null) ?? null;
    const targetTableSessionId = (targetTable.activeTableSessionId as string | null) ?? null;

    if (!sourceTableSessionId || !targetTableSessionId) {
      throw new HttpsError("failed-precondition", "Both tables must have an active session to merge — use transferTableSession to move a session onto a free table.");
    }
    if (sourceTableSessionId === targetTableSessionId) {
      return { targetTableSessionId, alreadyMerged: true };
    }

    const now = new Date();
    await requireNoForeignReservationConflict(db, tx, targetTableId, now);

    const sourceSessionRef = db.collection(TABLE_SESSIONS_COLLECTION).doc(sourceTableSessionId);
    const sourceSessionSnap = await tx.get(sourceSessionRef);
    if (!sourceSessionSnap.exists || sourceSessionSnap.data()!.status !== "active") {
      throw new HttpsError("failed-precondition", "The source table session is not active.");
    }
    const sourceSession = sourceSessionSnap.data()!;

    const [guestSessionsSnap, subAccountsSnap, checksSnap] = await Promise.all([
      tx.get(db.collection("tableGuestSessions").where("tableSessionId", "==", sourceTableSessionId)),
      tx.get(db.collection(GUEST_SUB_ACCOUNTS_COLLECTION).where("tableSessionId", "==", sourceTableSessionId)),
      tx.get(db.collection(CHECKS_COLLECTION).where("tableSessionId", "==", sourceTableSessionId)),
    ]);
    const checkIds = checksSnap.docs.map((d) => d.id);
    const allocationDocs: FirebaseFirestore.QueryDocumentSnapshot[] = [];
    for (let i = 0; i < checkIds.length; i += 30) {
      const chunk = checkIds.slice(i, i + 30);
      if (chunk.length === 0) continue;
      const snap = await tx.get(db.collection(CHECK_ALLOCATIONS_COLLECTION).where("checkId", "in", chunk));
      allocationDocs.push(...snap.docs);
    }

    const totalWrites = guestSessionsSnap.size + subAccountsSnap.size + checksSnap.size + allocationDocs.length + 3; // +3: source session, source table, target table
    if (totalWrites > MAX_SAFE_TRANSACTION_WRITES) {
      throw new HttpsError("resource-exhausted", "This merge would touch too many documents to complete safely in one transaction.");
    }

    const nowTs = Timestamp.fromDate(now);
    for (const doc of guestSessionsSnap.docs) tx.update(doc.ref, { tableId: targetTableId, tableSessionId: targetTableSessionId });
    for (const doc of subAccountsSnap.docs) tx.update(doc.ref, { tableSessionId: targetTableSessionId });
    for (const doc of checksSnap.docs) tx.update(doc.ref, { tableSessionId: targetTableSessionId });
    for (const doc of allocationDocs) tx.update(doc.ref, { tableSessionId: targetTableSessionId });

    tx.update(sourceSessionRef, { status: "closed", closedAt: nowTs, version: (sourceSession.version as number) + 1 });
    tx.update(sourceRef, { activeTableSessionId: null, status: "cleaning" });
    // targetRef itself needs no field change — it already points at targetTableSessionId and stays "occupied".
    void targetRef;

    writeAuditEvent({
      tx, db, eventId: `${sourceSessionRef.path.replace(/\//g, "_")}-merged-${Date.now()}`,
      organizationId: ctx.organizationId, branchId: ctx.branchId,
      type: "tableSession.merged", targetRef: `${TABLE_SESSIONS_COLLECTION}/${targetTableSessionId}`,
      newValue: { sourceTableId, sourceTableSessionId, targetTableId, targetTableSessionId, movedGuestSessions: guestSessionsSnap.size, movedSubAccounts: subAccountsSnap.size, movedChecks: checksSnap.size, movedAllocations: allocationDocs.length },
      actorType: "staff", actorUid: ctx.uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now: nowTs,
    });

    return {
      targetTableSessionId, alreadyMerged: false,
      movedGuestSessionCount: guestSessionsSnap.size, movedSubAccountCount: subAccountsSnap.size,
      movedCheckCount: checksSnap.size, movedAllocationCount: allocationDocs.length,
    };
  });
});
