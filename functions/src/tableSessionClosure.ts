import type { Firestore, Timestamp, Transaction } from "firebase-admin/firestore";
import { CHECKS_COLLECTION, type CheckStatus } from "./checkAllocationConfig";
import { TABLE_SESSIONS_COLLECTION } from "./tableSessionConfig";

/**
 * Dine-in Sprint 2 — shared "is this table session fully settled, and if so
 * release its table" logic. Reused by `checkOperations.ts`'s `cancelCheck`
 * and `paymentEngine.ts`'s `finalizeSessionIfComplete` (three call sites) —
 * both a check reaching `paid` and a check reaching `cancelled` can be the
 * event that makes an entire table session settled, so this lives here
 * rather than duplicated in either file (Reuse-First).
 *
 * Split into a read-only loader and a write-only releaser, mirroring this
 * codebase's own strict Firestore transaction discipline (every `tx.get()`
 * across a transaction must happen before any write) already used
 * identically by `checkOperations.ts`'s `syncTableBillRequestedOverride`
 * (Dine-in Sprint 1) and `paymentEngine.ts`'s own `attemptsForFinalize`
 * pattern.
 */

export interface TableClosureContext {
  ready: boolean;
  tableSessionRef: FirebaseFirestore.DocumentReference | null;
  tableSessionVersion: number;
  tableRef: FirebaseFirestore.DocumentReference | null;
}

export const NOT_READY_TABLE_CLOSURE: TableClosureContext = { ready: false, tableSessionRef: null, tableSessionVersion: 0, tableRef: null };
const NOT_READY = NOT_READY_TABLE_CLOSURE;

/**
 * READ-ONLY — call during the caller's own read phase, before any write in
 * that transaction. `settlingCheckId`/`settlingCheckNextStatus` let the
 * caller account for the one check it is ABOUT to make terminal, since that
 * write hasn't committed yet at read time (its own snapshot here still
 * shows the pre-transition status).
 *
 * Never throws — releasing the table is a best-effort side effect of a
 * check settling, not a precondition for that settlement itself.
 */
export async function loadTableClosureContext(
  db: Firestore,
  tx: Transaction,
  tableSessionId: string,
  settlingCheckId: string,
  settlingCheckNextStatus: Extract<CheckStatus, "paid" | "cancelled">,
): Promise<TableClosureContext> {
  const checksSnap = await tx.get(db.collection(CHECKS_COLLECTION).where("tableSessionId", "==", tableSessionId));
  const allTerminal = checksSnap.docs.every((doc) => {
    const status = doc.id === settlingCheckId ? settlingCheckNextStatus : (doc.data().status as CheckStatus);
    return status === "paid" || status === "cancelled";
  });
  if (!allTerminal) return NOT_READY;

  const tableSessionRef = db.collection(TABLE_SESSIONS_COLLECTION).doc(tableSessionId);
  const tableSessionSnap = await tx.get(tableSessionRef);
  if (!tableSessionSnap.exists) return NOT_READY;
  const tableId = tableSessionSnap.data()!.tableId as string | undefined;
  const tableSessionVersion = tableSessionSnap.data()!.version as number | undefined;
  if (!tableId || tableSessionVersion === undefined) return NOT_READY;

  const tableRef = db.collection("restaurantTables").doc(tableId);
  const tableSnap = await tx.get(tableRef);
  if (!tableSnap.exists) return NOT_READY;

  return { ready: true, tableSessionRef, tableSessionVersion, tableRef };
}

/**
 * WRITE-ONLY — no reads. Safe to call unconditionally; no-ops when
 * `ctx.ready` is false. `"cleaning"` (not `"available"`) matches
 * `transferTableSession`'s own existing convention — a table needs a
 * separate staff bussing step before it can accept a new QR session again
 * (`qrTokenResolution.ts`'s `status !== "available"` gate).
 */
export function releaseTableIfReady(tx: Transaction, ctx: TableClosureContext, now: Timestamp): void {
  if (!ctx.ready || !ctx.tableSessionRef || !ctx.tableRef) return;
  tx.update(ctx.tableSessionRef, { status: "closed", closedAt: now, version: ctx.tableSessionVersion + 1 });
  tx.update(ctx.tableRef, { activeTableSessionId: null, status: "cleaning", statusOverride: null });
}
