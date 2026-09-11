import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, type Transaction, type Firestore } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { requireActiveDeviceSession } from "./trustedDevice";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";
import { TABLE_SESSIONS_COLLECTION, GUEST_SUB_ACCOUNTS_COLLECTION } from "./tableSessionConfig";
import {
  CHECKS_COLLECTION,
  CHECK_ALLOCATIONS_COLLECTION,
  ORDER_LINE_ALLOCATION_LEDGERS_COLLECTION,
  orderLineAllocationLedgerId,
  isLineAllocatable,
  computeLineValueMinorUnits,
  type CheckDoc,
  type CheckAllocationDoc,
  type OrderLineAllocationLedgerDoc,
  type SourceCompositionEntry,
  type SplitMethod,
} from "./checkAllocationConfig";
import { allocateProportionally } from "./campaignPricing";
import { loadTableClosureContext, releaseTableIfReady } from "./tableSessionClosure";

/**
 * AP-3 Wave 2 — money-safe Check/allocation operations (corrected AP-3
 * Stage A report §2, Stage B mandatory refinement #3). Every mutating
 * callable here requires staff permission + branch access + an active
 * trusted-device session (corrected report §10.3/§F) — POS check/allocation
 * actions are exactly the "primary, action-taking" surface that boundary
 * targets, not the passive-monitoring exception (KDS board) left alone.
 */

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.length === 0) invalid(`${field} is required.`);
  return raw as string;
}
function requirePositiveInt(raw: unknown, field: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw <= 0) invalid(`${field} must be a positive integer.`);
  return raw as number;
}
function requireNonNegativeInt(raw: unknown, field: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < 0) invalid(`${field} must be a non-negative integer.`);
  return raw as number;
}

/** Deterministic largest-remainder even split of [total] across [count] equal-weight shares, in original order — a thin, correctly-shaped wrapper around `campaignPricing.ts`'s own proven `allocateProportionally` (never a hand-rolled division). */
function evenSplitMinorUnits(total: number, count: number): number[] {
  const weights = Array.from({ length: count }, (_, i) => ({ lineIndex: i, weight: 1 }));
  const result = allocateProportionally(total, weights);
  const byIndex = new Map(result.map((r) => [r.lineIndex, r.discountMinorUnits]));
  return Array.from({ length: count }, (_, i) => byIndex.get(i) ?? 0);
}

interface StaffDeviceContext {
  organizationId: string;
  branchId: string;
  uid: string;
}

async function authorizeStaffDeviceCommand(
  request: CallableRequest,
  data: Record<string, unknown>,
): Promise<StaffDeviceContext> {
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

// -----------------------------------------------------------------------
// Shared line/ledger pool helpers
// -----------------------------------------------------------------------

interface LinePoolEntry {
  sourceOrderId: string;
  sourceLineIndex: number;
  ledgerExists: boolean;
  originalQuantity: number;
  lineValueMinorUnits: number;
  remainingQuantity: number;
  remainingValueMinorUnits: number;
  currencyCode: string;
}

/**
 * Reads every accepted line under [tableSessionId] (across every order
 * whose `dineInSessionGroupId` matches it) plus, for each, its ledger if
 * one already exists — read-phase only, no writes. Deterministically
 * ordered (`sourceOrderId`, `sourceLineIndex`) so every caller that walks
 * this pool to satisfy a draw does so identically, run to run.
 */
async function loadLinePool(db: Firestore, tx: Transaction, tableSessionId: string): Promise<LinePoolEntry[]> {
  const ordersSnap = await tx.get(db.collection("orders").where("dineInSessionGroupId", "==", tableSessionId));
  const entries: LinePoolEntry[] = [];
  const ledgerReads: Promise<void>[] = [];
  for (const orderDoc of ordersSnap.docs) {
    const order = orderDoc.data();
    const lines = (order.lines ?? []) as Array<Record<string, unknown>>;
    lines.forEach((line, index) => {
      if (!isLineAllocatable(line as { status?: string })) return;
      const ledgerRef = db
        .collection(ORDER_LINE_ALLOCATION_LEDGERS_COLLECTION)
        .doc(orderLineAllocationLedgerId(orderDoc.id, index));
      ledgerReads.push(
        tx.get(ledgerRef).then((ledgerSnap) => {
          const lineValue = computeLineValueMinorUnits(
            line as { quantity: number; unitPrice?: { minorUnits: number }; lineDiscount?: { minorUnits: number }; modifiers?: Array<{ unitExtraPrice?: { minorUnits: number }; quantity: number }> },
          );
          if (ledgerSnap.exists) {
            const ledger = ledgerSnap.data() as OrderLineAllocationLedgerDoc;
            entries.push({
              sourceOrderId: orderDoc.id,
              sourceLineIndex: index,
              ledgerExists: true,
              originalQuantity: ledger.originalQuantity,
              lineValueMinorUnits: ledger.lineValueMinorUnits,
              remainingQuantity: ledger.remainingQuantity,
              remainingValueMinorUnits: ledger.remainingValueMinorUnits,
              currencyCode: ledger.currencyCode,
            });
          } else {
            entries.push({
              sourceOrderId: orderDoc.id,
              sourceLineIndex: index,
              ledgerExists: false,
              originalQuantity: line.quantity as number,
              lineValueMinorUnits: lineValue,
              remainingQuantity: line.quantity as number,
              remainingValueMinorUnits: lineValue,
              currencyCode: "TRY",
            });
          }
        }),
      );
    });
  }
  await Promise.all(ledgerReads);
  entries.sort((a, b) => (a.sourceOrderId === b.sourceOrderId ? a.sourceLineIndex - b.sourceLineIndex : a.sourceOrderId < b.sourceOrderId ? -1 : 1));
  return entries;
}

/** Draws up to [amountToDrawMinorUnits] across [pool] in deterministic order, mutating each consumed entry's remaining* fields in place and returning the composition. Never claims a `quantity` (whole-unit) share — money-only draw, for freeAmount/headcount splits. */
function drawValueFromPool(pool: LinePoolEntry[], amountToDrawMinorUnits: number): SourceCompositionEntry[] {
  const composition: SourceCompositionEntry[] = [];
  let remaining = amountToDrawMinorUnits;
  for (const entry of pool) {
    if (remaining <= 0) break;
    if (entry.remainingValueMinorUnits <= 0) continue;
    const draw = Math.min(remaining, entry.remainingValueMinorUnits);
    entry.remainingValueMinorUnits -= draw;
    remaining -= draw;
    composition.push({ sourceOrderId: entry.sourceOrderId, sourceLineIndex: entry.sourceLineIndex, quantity: null, amountMinorUnits: draw });
  }
  if (remaining > 0) {
    throw new HttpsError("failed-precondition", "Not enough remaining unallocated value on this check to satisfy the requested amount.");
  }
  return composition;
}

function ledgerWriteFor(entry: LinePoolEntry, ctx: { organizationId: string; branchId: string; tableSessionId: string }): OrderLineAllocationLedgerDoc {
  return {
    organizationId: ctx.organizationId,
    branchId: ctx.branchId,
    tableSessionId: ctx.tableSessionId,
    sourceOrderId: entry.sourceOrderId,
    sourceLineIndex: entry.sourceLineIndex,
    originalQuantity: entry.originalQuantity,
    lineValueMinorUnits: entry.lineValueMinorUnits,
    currencyCode: entry.currencyCode,
    remainingQuantity: entry.remainingQuantity,
    remainingValueMinorUnits: entry.remainingValueMinorUnits,
    version: 1,
  };
}

/** One shared audit-event writer for every Check/allocation mutation in this file — mirrors `respondToDineInOrderLines.ts`'s own inline shape, factored out here since this file has many more distinct mutation types. */
function auditCheckEvent(
  tx: Transaction,
  db: Firestore,
  params: { type: string; targetRef: string; organizationId: string; branchId: string; actorUid: string; newValue?: unknown; clientRequestId?: unknown
  },
): void {
  writeAuditEvent({
    tx,
    db,
    // `targetRef` is a Firestore document PATH (contains `/`) — a raw `/`
    // inside a doc id makes `.doc(id)` misparse it as a multi-segment
    // path ("path does not contain an even number of components").
    // Sanitized exactly like `remoteApproval.ts`'s own
    // `targetAggregateRef.replace(/\//g, "_")` precedent.
    eventId: `${params.targetRef.replace(/\//g, "_")}-${params.type}-${Date.now()}-${Math.random().toString(36).slice(2, 8)}`,
    organizationId: params.organizationId,
    branchId: params.branchId,
    type: params.type,
    targetRef: params.targetRef,
    newValue: params.newValue,
    actorType: "staff",
    actorUid: params.actorUid,
    correlationId: generateCorrelationId(),
    clientRequestId: sanitizeClientRequestId(params.clientRequestId),
    now: Timestamp.now(),
  });
}

async function loadCheckOrThrow(db: Firestore, tx: Transaction, checkId: string, organizationId: string, branchId: string): Promise<{ ref: FirebaseFirestore.DocumentReference; data: CheckDoc }> {
  const ref = db.collection(CHECKS_COLLECTION).doc(checkId);
  const snap = await tx.get(ref);
  if (!snap.exists) throw new HttpsError("not-found", "Check not found.");
  const check = snap.data() as CheckDoc;
  if (check.organizationId !== organizationId || check.branchId !== branchId) {
    throw new HttpsError("not-found", "Check not found.");
  }
  return { ref, data: check };
}

async function sumActiveAllocations(db: Firestore, tx: Transaction, checkId: string): Promise<number> {
  const snap = await tx.get(db.collection(CHECK_ALLOCATIONS_COLLECTION).where("checkId", "==", checkId).where("status", "==", "active"));
  return snap.docs.reduce((sum, d) => sum + (d.data().allocatedAmountMinorUnits as number), 0);
}

/**
 * Reads-then-writes the `billRequested` override on the check's physical
 * table (`restaurantTables/{tableId}.statusOverride`), which
 * `posOperationalView.ts` already derives `status` from
 * (`statusOverride ?? status`). All reads here happen before any caller
 * write, matching this transaction's own read-before-write discipline.
 *
 * A table session can have multiple split checks — clearing the override
 * (finalizing -> false) only clears it when no OTHER check on the same
 * table session is still `readyForPayment`, so reopening one split check
 * doesn't drop the "bill requested" signal while a sibling split is still
 * awaiting payment.
 */
async function syncTableBillRequestedOverride(
  db: Firestore,
  tx: Transaction,
  check: CheckDoc,
  checkId: string,
  wantsBillRequested: boolean,
): Promise<void> {
  const tableSessionId = check.tableSessionId;
  if (!tableSessionId) return;

  const tableSessionSnap = await tx.get(db.collection(TABLE_SESSIONS_COLLECTION).doc(tableSessionId));
  const tableId = tableSessionSnap.data()?.tableId as string | undefined;
  if (!tableId) return;
  const tableRef = db.collection("restaurantTables").doc(tableId);
  const tableSnap = await tx.get(tableRef);
  if (!tableSnap.exists) return;

  if (wantsBillRequested) {
    tx.update(tableRef, { statusOverride: "billRequested" });
    return;
  }

  const otherReadyChecksSnap = await tx.get(
    db.collection(CHECKS_COLLECTION).where("tableSessionId", "==", tableSessionId).where("status", "==", "readyForPayment"),
  );
  const stillHasOtherReadyCheck = otherReadyChecksSnap.docs.some((d) => d.id !== checkId);
  if (!stillHasOtherReadyCheck) {
    tx.update(tableRef, { statusOverride: null });
  }
}

/** Writes one new allocation + its ledger updates + the check's recomputed total, inside the caller's already-open transaction. Assumes every read the caller needs has already happened. */
function writeAllocation(
  tx: Transaction,
  db: Firestore,
  params: {
    checkRef: FirebaseFirestore.DocumentReference;
    check: CheckDoc;
    subAccountId: string;
    splitMethod: SplitMethod;
    sourceComposition: SourceCompositionEntry[];
    consumedPoolEntries: LinePoolEntry[];
    note: string | null;
    actorUid: string;
    priorActiveTotal: number;
  },
): string {
  const allocatedAmountMinorUnits = params.sourceComposition.reduce((s, e) => s + e.amountMinorUnits, 0);
  const allocationRef = db.collection(CHECK_ALLOCATIONS_COLLECTION).doc();
  const now = Timestamp.now();
  const allocation: CheckAllocationDoc = {
    checkId: params.checkRef.id,
    organizationId: params.check.organizationId,
    branchId: params.check.branchId,
    tableSessionId: params.check.tableSessionId,
    subAccountId: params.subAccountId,
    splitMethod: params.splitMethod,
    sourceComposition: params.sourceComposition,
    allocatedAmountMinorUnits,
    currencyCode: params.check.currencyCode,
    status: "active",
    note: params.note,
    createdAt: now,
    createdByStaffUid: params.actorUid,
    version: 1,
  };
  tx.set(allocationRef, allocation);
  for (const entry of params.consumedPoolEntries) {
    tx.set(
      db.collection(ORDER_LINE_ALLOCATION_LEDGERS_COLLECTION).doc(orderLineAllocationLedgerId(entry.sourceOrderId, entry.sourceLineIndex)),
      ledgerWriteFor(entry, { organizationId: params.check.organizationId, branchId: params.check.branchId, tableSessionId: params.check.tableSessionId }),
      { merge: true },
    );
  }
  tx.update(params.checkRef, {
    computedTotalMinorUnits: params.priorActiveTotal + allocatedAmountMinorUnits,
    version: params.check.version + 1,
  });
  auditCheckEvent(tx, db, {
    type: `checkAllocation.created.${params.splitMethod}`,
    targetRef: allocationRef.path,
    organizationId: params.check.organizationId,
    branchId: params.check.branchId,
    actorUid: params.actorUid,
    newValue: { subAccountId: params.subAccountId, allocatedAmountMinorUnits },
  });
  return allocationRef.id;
}

// -----------------------------------------------------------------------
// Check lifecycle
// -----------------------------------------------------------------------

export const openCheck = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeStaffDeviceCommand(request, data);
  const tableSessionId = requireNonEmptyString(data.tableSessionId, "tableSessionId");

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const tableSessionSnap = await tx.get(db.collection(TABLE_SESSIONS_COLLECTION).doc(tableSessionId));
    if (!tableSessionSnap.exists || tableSessionSnap.data()!.status !== "active") {
      throw new HttpsError("failed-precondition", "This table session is not active.");
    }
    const tableSession = tableSessionSnap.data()!;
    if (tableSession.organizationId !== ctx.organizationId || tableSession.branchId !== ctx.branchId) {
      throw new HttpsError("not-found", "Table session not found.");
    }
    const checkRef = db.collection(CHECKS_COLLECTION).doc();
    const now = Timestamp.now();
    const check: CheckDoc = {
      organizationId: ctx.organizationId,
      branchId: ctx.branchId,
      tableSessionId,
      status: "open",
      paymentActivityStarted: false,
      computedTotalMinorUnits: 0,
      currencyCode: "TRY",
      openedAt: now,
      readyForPaymentAt: null,
      cancelledAt: null,
      createdByStaffUid: ctx.uid,
      version: 1,
    };
    tx.set(checkRef, check);
    auditCheckEvent(tx, db, { type: "check.opened", targetRef: checkRef.path, organizationId: ctx.organizationId, branchId: ctx.branchId, actorUid: ctx.uid });
    return { checkId: checkRef.id };
  });
});

export const cancelCheck = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeStaffDeviceCommand(request, data);
  const checkId = requireNonEmptyString(data.checkId, "checkId");

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { ref, data: check } = await loadCheckOrThrow(db, tx, checkId, ctx.organizationId, ctx.branchId);
    if (check.status !== "open") throw new HttpsError("failed-precondition", "Only an open check may be cancelled.");
    const activeCount = (await tx.get(db.collection(CHECK_ALLOCATIONS_COLLECTION).where("checkId", "==", checkId).where("status", "==", "active"))).size;
    if (activeCount > 0) {
      throw new HttpsError("failed-precondition", "This check still has active allocations — remove them before cancelling.");
    }
    const closureCtx = await loadTableClosureContext(db, tx, check.tableSessionId, checkId, "cancelled");
    const now = Timestamp.now();
    tx.update(ref, { status: "cancelled", cancelledAt: now, version: check.version + 1 });
    releaseTableIfReady(tx, closureCtx, now);
    auditCheckEvent(tx, db, { type: "check.cancelled", targetRef: ref.path, organizationId: ctx.organizationId, branchId: ctx.branchId, actorUid: ctx.uid });
    return { checkId, status: "cancelled" };
  });
});

export const finalizeCheckReadyForPayment = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeStaffDeviceCommand(request, data);
  const checkId = requireNonEmptyString(data.checkId, "checkId");

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { ref, data: check } = await loadCheckOrThrow(db, tx, checkId, ctx.organizationId, ctx.branchId);
    if (check.status !== "open") throw new HttpsError("failed-precondition", "Only an open check may be finalized.");

    const allocationsSnap = await tx.get(db.collection(CHECK_ALLOCATIONS_COLLECTION).where("checkId", "==", checkId).where("status", "==", "active"));
    if (allocationsSnap.empty) {
      throw new HttpsError("failed-precondition", "A check with no active allocations cannot be finalized.");
    }
    // Every referenced source order must have every one of ITS OWN lines in
    // a terminal state (accepted/rejected) — a still-pendingApproval line
    // anywhere on an order this check draws from means the check's own
    // eventual total isn't settled yet.
    const orderIds = new Set<string>();
    for (const doc of allocationsSnap.docs) {
      for (const entry of (doc.data().sourceComposition as SourceCompositionEntry[])) orderIds.add(entry.sourceOrderId);
    }
    for (const orderId of orderIds) {
      const orderSnap = await tx.get(db.collection("orders").doc(orderId));
      const lines = (orderSnap.data()?.lines ?? []) as Array<{ status: string }>;
      if (lines.some((l) => l.status === "pendingApproval" || l.status === "proposedChange")) {
        throw new HttpsError("failed-precondition", "An order this check draws from still has an undecided line.");
      }
    }

    const subAccountIds = new Set(allocationsSnap.docs.map((d) => d.data().subAccountId as string));
    await syncTableBillRequestedOverride(db, tx, check, checkId, true);
    const now = Timestamp.now();
    tx.update(ref, { status: "readyForPayment", readyForPaymentAt: now, version: check.version + 1 });
    for (const subAccountId of subAccountIds) {
      tx.set(db.collection(GUEST_SUB_ACCOUNTS_COLLECTION).doc(subAccountId), { status: "closed" }, { merge: true });
    }
    auditCheckEvent(tx, db, { type: "check.readyForPayment", targetRef: ref.path, organizationId: ctx.organizationId, branchId: ctx.branchId, actorUid: ctx.uid });
    return { checkId, status: "readyForPayment" };
  });
});

export const reopenCheck = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeStaffDeviceCommand(request, data);
  const checkId = requireNonEmptyString(data.checkId, "checkId");

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { ref, data: check } = await loadCheckOrThrow(db, tx, checkId, ctx.organizationId, ctx.branchId);
    if (check.status !== "readyForPayment") throw new HttpsError("failed-precondition", "Only a readyForPayment check may be reopened.");
    if (check.paymentActivityStarted) {
      throw new HttpsError("failed-precondition", "Payment activity has already started on this check — reopening requires manager remote approval (not yet reachable through this callable).");
    }
    await syncTableBillRequestedOverride(db, tx, check, checkId, false);
    tx.update(ref, { status: "open", readyForPaymentAt: null, version: check.version + 1 });
    auditCheckEvent(tx, db, { type: "check.reopened", targetRef: ref.path, organizationId: ctx.organizationId, branchId: ctx.branchId, actorUid: ctx.uid });
    return { checkId, status: "open" };
  });
});

// -----------------------------------------------------------------------
// Split modes — five distinctly-named, distinctly-tested wrappers around
// the shared pool/ledger/allocation-write primitives above.
// -----------------------------------------------------------------------

async function requireOpenUnlockedCheck(db: Firestore, tx: Transaction, checkId: string, ctx: StaffDeviceContext) {
  const { ref, data: check } = await loadCheckOrThrow(db, tx, checkId, ctx.organizationId, ctx.branchId);
  if (check.status !== "open") throw new HttpsError("failed-precondition", "This check is not open.");
  if (check.paymentActivityStarted) {
    throw new HttpsError("failed-precondition", "Payment activity has already started — this action requires manager remote approval.");
  }
  return { ref, check };
}

async function requireSubAccountInSession(db: Firestore, tx: Transaction, subAccountId: string, tableSessionId: string) {
  const snap = await tx.get(db.collection(GUEST_SUB_ACCOUNTS_COLLECTION).doc(subAccountId));
  if (!snap.exists || snap.data()!.tableSessionId !== tableSessionId) {
    throw new HttpsError("not-found", "The selected sub-account does not exist at this table session.");
  }
}

export const splitCheckByProduct = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeStaffDeviceCommand(request, data);
  const checkId = requireNonEmptyString(data.checkId, "checkId");
  const subAccountId = requireNonEmptyString(data.subAccountId, "subAccountId");
  const sourceOrderId = requireNonEmptyString(data.sourceOrderId, "sourceOrderId");
  const sourceLineIndex = requireNonNegativeInt(data.sourceLineIndex, "sourceLineIndex");
  const note = typeof data.note === "string" ? data.note : null;

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { ref: checkRef, check } = await requireOpenUnlockedCheck(db, tx, checkId, ctx);
    await requireSubAccountInSession(db, tx, subAccountId, check.tableSessionId);
    const pool = await loadLinePool(db, tx, check.tableSessionId);
    const entry = pool.find((e) => e.sourceOrderId === sourceOrderId && e.sourceLineIndex === sourceLineIndex);
    if (!entry) throw new HttpsError("not-found", "That order line is not allocatable under this check's table session.");
    if (entry.remainingQuantity <= 0 || entry.remainingValueMinorUnits <= 0) {
      throw new HttpsError("failed-precondition", "This line has already been fully allocated.");
    }
    const priorTotal = await sumActiveAllocations(db, tx, checkId);
    const composition: SourceCompositionEntry[] = [
      { sourceOrderId, sourceLineIndex, quantity: entry.remainingQuantity, amountMinorUnits: entry.remainingValueMinorUnits },
    ];
    entry.remainingQuantity = 0;
    entry.remainingValueMinorUnits = 0;
    const allocationId = writeAllocation(tx, db, {
      checkRef, check, subAccountId, splitMethod: "product", sourceComposition: composition,
      consumedPoolEntries: [entry], note, actorUid: ctx.uid, priorActiveTotal: priorTotal,
    });
    return { allocationId };
  });
});

export const splitCheckByQuantity = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeStaffDeviceCommand(request, data);
  const checkId = requireNonEmptyString(data.checkId, "checkId");
  const subAccountId = requireNonEmptyString(data.subAccountId, "subAccountId");
  const sourceOrderId = requireNonEmptyString(data.sourceOrderId, "sourceOrderId");
  const sourceLineIndex = requireNonNegativeInt(data.sourceLineIndex, "sourceLineIndex");
  const quantity = requirePositiveInt(data.quantity, "quantity");
  const note = typeof data.note === "string" ? data.note : null;

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { ref: checkRef, check } = await requireOpenUnlockedCheck(db, tx, checkId, ctx);
    await requireSubAccountInSession(db, tx, subAccountId, check.tableSessionId);
    const pool = await loadLinePool(db, tx, check.tableSessionId);
    const entry = pool.find((e) => e.sourceOrderId === sourceOrderId && e.sourceLineIndex === sourceLineIndex);
    if (!entry) throw new HttpsError("not-found", "That order line is not allocatable under this check's table session.");
    if (quantity > entry.remainingQuantity) {
      throw new HttpsError("failed-precondition", `Only ${entry.remainingQuantity} unit(s) of this line remain unallocated.`);
    }
    // Deterministic per-unit value (largest-remainder apportionment of the
    // line's ORIGINAL total across its ORIGINAL quantity) — never a naive
    // `value / quantity` division, which would silently drop remainder
    // minor units on a line whose value doesn't divide evenly.
    const perUnitShares = evenSplitMinorUnits(entry.lineValueMinorUnits, entry.originalQuantity);
    const alreadyConsumedUnits = entry.originalQuantity - entry.remainingQuantity;
    const amountMinorUnits = perUnitShares.slice(alreadyConsumedUnits, alreadyConsumedUnits + quantity).reduce((s, v) => s + v, 0);
    if (amountMinorUnits > entry.remainingValueMinorUnits) {
      throw new HttpsError("internal", "Allocation value exceeds remaining line value — apportionment invariant violated.");
    }
    const priorTotal = await sumActiveAllocations(db, tx, checkId);
    entry.remainingQuantity -= quantity;
    entry.remainingValueMinorUnits -= amountMinorUnits;
    const allocationId = writeAllocation(tx, db, {
      checkRef, check, subAccountId, splitMethod: "quantity",
      sourceComposition: [{ sourceOrderId, sourceLineIndex, quantity, amountMinorUnits }],
      consumedPoolEntries: [entry], note, actorUid: ctx.uid, priorActiveTotal: priorTotal,
    });
    return { allocationId };
  });
});

export const splitCheckByCustomer = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeStaffDeviceCommand(request, data);
  const checkId = requireNonEmptyString(data.checkId, "checkId");
  const subAccountId = requireNonEmptyString(data.subAccountId, "subAccountId");
  const note = typeof data.note === "string" ? data.note : null;

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { ref: checkRef, check } = await requireOpenUnlockedCheck(db, tx, checkId, ctx);
    await requireSubAccountInSession(db, tx, subAccountId, check.tableSessionId);
    const pool = await loadLinePool(db, tx, check.tableSessionId);

    // Which lines belong to this identity — read the orders again (cheap,
    // already fetched by loadLinePool's own query; re-deriving ownership
    // here keeps loadLinePool itself identity-agnostic and reusable).
    const ordersSnap = await tx.get(db.collection("orders").where("dineInSessionGroupId", "==", check.tableSessionId));
    const ownedLineKeys = new Set<string>();
    for (const orderDoc of ordersSnap.docs) {
      const lines = (orderDoc.data().lines ?? []) as Array<{ subAccountId?: string }>;
      lines.forEach((line, index) => {
        if (line.subAccountId === subAccountId) ownedLineKeys.add(`${orderDoc.id}_${index}`);
      });
    }

    const consumed: LinePoolEntry[] = [];
    const composition: SourceCompositionEntry[] = [];
    for (const entry of pool) {
      if (!ownedLineKeys.has(`${entry.sourceOrderId}_${entry.sourceLineIndex}`)) continue;
      if (entry.remainingValueMinorUnits <= 0) continue;
      composition.push({
        sourceOrderId: entry.sourceOrderId, sourceLineIndex: entry.sourceLineIndex,
        quantity: entry.remainingQuantity, amountMinorUnits: entry.remainingValueMinorUnits,
      });
      entry.remainingQuantity = 0;
      entry.remainingValueMinorUnits = 0;
      consumed.push(entry);
    }
    if (composition.length === 0) {
      throw new HttpsError("failed-precondition", "This sub-account has no remaining unallocated lines under this table session.");
    }
    const priorTotal = await sumActiveAllocations(db, tx, checkId);
    const allocationId = writeAllocation(tx, db, {
      checkRef, check, subAccountId, splitMethod: "customer", sourceComposition: composition,
      consumedPoolEntries: consumed, note, actorUid: ctx.uid, priorActiveTotal: priorTotal,
    });
    return { allocationId };
  });
});

export const splitCheckEqualByHeadcount = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeStaffDeviceCommand(request, data);
  const checkId = requireNonEmptyString(data.checkId, "checkId");
  const subAccountIds = Array.isArray(data.subAccountIds) ? (data.subAccountIds as unknown[]) : [];
  if (subAccountIds.length < 2 || !subAccountIds.every((v) => typeof v === "string" && v.length > 0)) {
    invalid("subAccountIds must contain at least 2 sub-account ids.");
  }
  const note = typeof data.note === "string" ? data.note : null;

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { ref: checkRef, check } = await requireOpenUnlockedCheck(db, tx, checkId, ctx);
    for (const id of subAccountIds as string[]) await requireSubAccountInSession(db, tx, id, check.tableSessionId);
    const pool = await loadLinePool(db, tx, check.tableSessionId);
    const totalAvailable = pool.reduce((s, e) => s + e.remainingValueMinorUnits, 0);
    if (totalAvailable <= 0) throw new HttpsError("failed-precondition", "Nothing remains unallocated on this table session.");

    // Largest-remainder apportionment of the available total across N
    // people — the exact same primitive already proven for campaign
    // discount distribution, reused verbatim.
    const shares = evenSplitMinorUnits(totalAvailable, (subAccountIds as string[]).length);

    const priorTotal = await sumActiveAllocations(db, tx, checkId);
    let runningPriorTotal = priorTotal;
    const allocationIds: string[] = [];
    for (let i = 0; i < shares.length; i++) {
      const composition = drawValueFromPool(pool, shares[i]);
      const consumedKeys = new Set(composition.map((c) => `${c.sourceOrderId}_${c.sourceLineIndex}`));
      const consumedEntries = pool.filter((e) => consumedKeys.has(`${e.sourceOrderId}_${e.sourceLineIndex}`));
      const allocationId = writeAllocation(tx, db, {
        checkRef, check, subAccountId: (subAccountIds as string[])[i], splitMethod: "headcount",
        sourceComposition: composition, consumedPoolEntries: consumedEntries, note,
        actorUid: ctx.uid, priorActiveTotal: runningPriorTotal,
      });
      runningPriorTotal += shares[i];
      allocationIds.push(allocationId);
    }
    return { allocationIds };
  });
});

export const splitCheckFreeAmount = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeStaffDeviceCommand(request, data);
  const checkId = requireNonEmptyString(data.checkId, "checkId");
  const subAccountId = requireNonEmptyString(data.subAccountId, "subAccountId");
  const amountMinorUnits = requirePositiveInt(data.amountMinorUnits, "amountMinorUnits");
  const note = typeof data.note === "string" ? data.note : null;

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { ref: checkRef, check } = await requireOpenUnlockedCheck(db, tx, checkId, ctx);
    await requireSubAccountInSession(db, tx, subAccountId, check.tableSessionId);
    const pool = await loadLinePool(db, tx, check.tableSessionId);
    const composition = drawValueFromPool(pool, amountMinorUnits);
    const consumedKeys = new Set(composition.map((c) => `${c.sourceOrderId}_${c.sourceLineIndex}`));
    const consumedEntries = pool.filter((e) => consumedKeys.has(`${e.sourceOrderId}_${e.sourceLineIndex}`));
    const priorTotal = await sumActiveAllocations(db, tx, checkId);
    const allocationId = writeAllocation(tx, db, {
      checkRef, check, subAccountId, splitMethod: "freeAmount", sourceComposition: composition,
      consumedPoolEntries: consumedEntries, note, actorUid: ctx.uid, priorActiveTotal: priorTotal,
    });
    return { allocationId };
  });
});

// -----------------------------------------------------------------------
// Merge / transfer
// -----------------------------------------------------------------------

/** Moves every active allocation from [sourceCheckId] onto [targetCheckId] — a pure reallocation, both checks' totals are re-derived from their own (now-updated) active-allocation sets, never independently re-priced. */
export const mergeChecks = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeStaffDeviceCommand(request, data);
  const sourceCheckId = requireNonEmptyString(data.sourceCheckId, "sourceCheckId");
  const targetCheckId = requireNonEmptyString(data.targetCheckId, "targetCheckId");
  if (sourceCheckId === targetCheckId) invalid("sourceCheckId and targetCheckId must differ.");

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { ref: sourceRef, check: sourceCheck } = await requireOpenUnlockedCheck(db, tx, sourceCheckId, ctx);
    const { ref: targetRef, check: targetCheck } = await requireOpenUnlockedCheck(db, tx, targetCheckId, ctx);
    if (sourceCheck.tableSessionId !== targetCheck.tableSessionId) {
      throw new HttpsError("failed-precondition", "Only checks belonging to the same table session may be merged.");
    }
    const allocationsSnap = await tx.get(db.collection(CHECK_ALLOCATIONS_COLLECTION).where("checkId", "==", sourceCheckId).where("status", "==", "active"));
    const movedTotal = allocationsSnap.docs.reduce((s, d) => s + (d.data().allocatedAmountMinorUnits as number), 0);
    for (const doc of allocationsSnap.docs) {
      tx.update(doc.ref, { checkId: targetCheckId, version: (doc.data().version as number) + 1 });
    }
    tx.update(sourceRef, { status: "cancelled", cancelledAt: Timestamp.now(), computedTotalMinorUnits: 0, version: sourceCheck.version + 1 });
    tx.update(targetRef, { computedTotalMinorUnits: targetCheck.computedTotalMinorUnits + movedTotal, version: targetCheck.version + 1 });
    auditCheckEvent(tx, db, {
      type: "check.merged", targetRef: targetRef.path, organizationId: ctx.organizationId, branchId: ctx.branchId,
      actorUid: ctx.uid, newValue: { sourceCheckId, movedTotal, movedAllocationCount: allocationsSnap.size },
    });
    return { movedAllocationCount: allocationsSnap.size, movedTotalMinorUnits: movedTotal };
  });
});

/** Moves exactly one allocation to a different check under the SAME table session — a value-preserving reallocation, not a new claim on source-line value (the ledger is untouched). */
export const transferCheckAllocation = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const ctx = await authorizeStaffDeviceCommand(request, data);
  const allocationId = requireNonEmptyString(data.allocationId, "allocationId");
  const targetCheckId = requireNonEmptyString(data.targetCheckId, "targetCheckId");

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const allocationRef = db.collection(CHECK_ALLOCATIONS_COLLECTION).doc(allocationId);
    const allocationSnap = await tx.get(allocationRef);
    if (!allocationSnap.exists) throw new HttpsError("not-found", "Allocation not found.");
    const allocation = allocationSnap.data() as CheckAllocationDoc;
    if (allocation.organizationId !== ctx.organizationId || allocation.branchId !== ctx.branchId) {
      throw new HttpsError("not-found", "Allocation not found.");
    }
    if (allocation.status !== "active") throw new HttpsError("failed-precondition", "Only an active allocation may be transferred.");
    const { ref: sourceRef, check: sourceCheck } = await requireOpenUnlockedCheck(db, tx, allocation.checkId, ctx);
    const { ref: targetRef, check: targetCheck } = await requireOpenUnlockedCheck(db, tx, targetCheckId, ctx);
    if (sourceCheck.tableSessionId !== targetCheck.tableSessionId) {
      throw new HttpsError("failed-precondition", "The target check must belong to the same table session.");
    }
    tx.update(allocationRef, { checkId: targetCheckId, version: allocation.version + 1 });
    tx.update(sourceRef, { computedTotalMinorUnits: sourceCheck.computedTotalMinorUnits - allocation.allocatedAmountMinorUnits, version: sourceCheck.version + 1 });
    tx.update(targetRef, { computedTotalMinorUnits: targetCheck.computedTotalMinorUnits + allocation.allocatedAmountMinorUnits, version: targetCheck.version + 1 });
    auditCheckEvent(tx, db, {
      type: "checkAllocation.transferred", targetRef: allocationRef.path, organizationId: ctx.organizationId, branchId: ctx.branchId,
      actorUid: ctx.uid, newValue: { fromCheckId: allocation.checkId, toCheckId: targetCheckId, amountMinorUnits: allocation.allocatedAmountMinorUnits },
    });
    return { allocationId, movedAmountMinorUnits: allocation.allocatedAmountMinorUnits };
  });
});
