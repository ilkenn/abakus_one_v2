import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { requireActiveDeviceSession } from "./trustedDevice";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";
import { createApprovalRequest } from "./remoteApproval";
import type { ActionHandlerParams, ActionHandlerResult } from "./remoteApproval";
import { CHECKS_COLLECTION, type CheckDoc } from "./checkAllocationConfig";
import { GUEST_SUB_ACCOUNTS_COLLECTION, type GuestSubAccountDoc } from "./tableSessionConfig";
import { LOYALTY_ACCOUNTS_COLLECTION, LOYALTY_LEDGER_ENTRIES_COLLECTION, deriveLoyaltyLedgerEntryId, type LoyaltyLedgerEntry } from "./loyaltyLedger";
import { allocateProportionally } from "./campaignPricing";
import {
  PAYMENT_ATTEMPTS_COLLECTION,
  REFUND_REQUESTS_COLLECTION,
  isAttemptSettled,
  type PaymentAttemptDoc,
  type RefundRequestDoc,
  type RefundAllocationEntry,
  type RefundType,
} from "./paymentDomain";

/**
 * AP-4 Wave A — refund architecture (ADR-033). Full + selected-item/
 * quantity partial refund; mixed-tender apportionment via the SAME
 * deterministic largest-remainder helper `checkOperations.ts`'s campaign
 * discount allocation already uses (`campaignPricing.ts`'s
 * `allocateProportionally`) — never a hand-rolled rounding scheme.
 *
 * **Refund execution per tender, honestly scoped**: `cash` settles
 * synchronously (a real physical hand-back, confirmed by the approving
 * manager — Wave B's real `CashMovement` Firestore backing will attach a
 * genuine negative movement here once it exists; `cashMovementId` stays
 * `null` until then, disclosed, not fabricated). `boncuk` is a real,
 * complete restoration through the existing closed loyalty ledger
 * mechanism — no different from any other Boncuk ledger write in this
 * codebase. `card`/`mealCard` use the same CERTIFICATION-ONLY fallback
 * `refundTakeawayOrder.ts` (etc.) already established for the identical
 * reason: no real payment provider is configured (BR-PAY-003) — this
 * function records that a refund was externally certified as having
 * happened, it does not and cannot execute a real provider reversal that
 * doesn't exist. Never presented as equivalent to a real provider refund.
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

export const requestPaymentRefund = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
  const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");
  const checkId = requireNonEmptyString(data.checkId, "checkId");
  const refundType = (data.refundType === "full" || data.refundType === "partial" ? data.refundType : invalid('refundType must be "full" or "partial".')) as RefundType;
  const amountMinorUnits = requirePositiveInt(data.amountMinorUnits, "amountMinorUnits");
  const orderLineRefs = refundType === "partial" && Array.isArray(data.orderLineRefs) ? (data.orderLineRefs as string[]) : null;
  const reasonCode = requireNonEmptyString(data.reasonCode, "reasonCode");
  const reasonMessage = requireNonEmptyString(data.reasonMessage, "reasonMessage");

  requireStaffPermission(request, organizationId, "processPayments");
  requireBranchAccess(request, organizationId, branchId);
  await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const checkRef = db.collection(CHECKS_COLLECTION).doc(checkId);
    const checkSnap = await tx.get(checkRef);
    if (!checkSnap.exists) throw new HttpsError("not-found", "Check not found.");
    const check = checkSnap.data() as CheckDoc;
    if (check.organizationId !== organizationId || check.branchId !== branchId) throw new HttpsError("not-found", "Check not found.");
    if (check.status !== "paid") {
      throw new HttpsError("failed-precondition", `A refund may only be requested against a "paid" check (current: "${check.status}").`);
    }

    const attemptsSnap = await tx.get(db.collection(PAYMENT_ATTEMPTS_COLLECTION).where("checkId", "==", checkId));
    const succeededAttempts = attemptsSnap.docs
      .map((d) => ({ id: d.id, data: d.data() as PaymentAttemptDoc }))
      .filter((a) => isAttemptSettled(a.data.status));
    if (succeededAttempts.length === 0) throw new HttpsError("failed-precondition", "This check has no settled payment attempts to refund.");

    const priorRequestsSnap = await tx.get(
      db.collection(REFUND_REQUESTS_COLLECTION).where("checkId", "==", checkId).where("status", "!=", "failed"),
    );
    const alreadyRefundedByAttempt = new Map<string, number>();
    for (const doc of priorRequestsSnap.docs) {
      const req = doc.data() as RefundRequestDoc;
      for (const alloc of req.allocations) {
        if (alloc.status === "resolvedFailed") continue;
        alreadyRefundedByAttempt.set(alloc.originalAttemptId, (alreadyRefundedByAttempt.get(alloc.originalAttemptId) ?? 0) + alloc.amountMinorUnits);
      }
    }

    const weights = succeededAttempts.map((a, index) => {
      const alreadyRefunded = alreadyRefundedByAttempt.get(a.id) ?? 0;
      const refundable = a.data.amountMinorUnits - alreadyRefunded;
      return { lineIndex: index, weight: Math.max(refundable, 0), attemptId: a.id, tenderType: a.data.tenderType, refundable };
    });
    const totalRefundable = weights.reduce((s, w) => s + w.refundable, 0);
    if (amountMinorUnits > totalRefundable) {
      throw new HttpsError("failed-precondition", `Requested refund (${amountMinorUnits}) exceeds the total refundable amount (${totalRefundable}).`, { code: "refund/exceeds-refundable" });
    }

    const apportioned = allocateProportionally(amountMinorUnits, weights.map((w) => ({ lineIndex: w.lineIndex, weight: w.weight })));
    const allocations: RefundAllocationEntry[] = apportioned
      .filter((a) => a.discountMinorUnits > 0)
      .map((a) => {
        const w = weights[a.lineIndex];
        return {
          originalAttemptId: w.attemptId, tenderType: w.tenderType, amountMinorUnits: a.discountMinorUnits,
          status: "providerPending" as const, providerRef: null, cashMovementId: null, loyaltyLedgerEntryId: null,
        };
      });

    const refundId = db.collection(REFUND_REQUESTS_COLLECTION).doc().id;
    const refundRef = db.collection(REFUND_REQUESTS_COLLECTION).doc(refundId);
    const now = Timestamp.now();
    const refund: RefundRequestDoc = {
      organizationId, branchId, checkId, refundType, orderLineRefs, amountMinorUnits, allocations,
      status: "pendingApproval", reasonCode, reasonMessage, requestedByStaffUid: request.auth!.uid,
      approvalRequestRef: null, createdAt: now, resolvedAt: null, version: 1,
    };
    tx.set(refundRef, refund);

    writeAuditEvent({
      tx, db, eventId: `${refundId}-requested`,
      organizationId, branchId, type: "paymentRefund.requested", targetRef: refundRef.path,
      newValue: { checkId, amountMinorUnits, refundType },
      actorType: "staff", actorUid: request.auth!.uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });

    return { refundId, checkId, amountMinorUnits, status: "pendingApproval" as const };
  }).then(async (result) => {
    const approval = await createApprovalRequest({
      organizationId, branchId, actionType: "paymentRefund",
      requestedByActorUid: request.auth!.uid,
      targetAggregateRef: db.collection(REFUND_REQUESTS_COLLECTION).doc(result.refundId).path,
      targetAggregateVersion: 1,
      payloadHash: `${checkId}-${amountMinorUnits}`,
    });
    await db.collection(REFUND_REQUESTS_COLLECTION).doc(result.refundId).update({ approvalRequestRef: approval.requestId });
    return { ...result, approvalRequestId: approval.requestId };
  });
});

/** The allowlisted `paymentRefund` remote-approval handler — the ONLY writer that actually moves refund money. */
export async function applyPaymentRefund(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, request: approval, now, respondedByActorUid } = params;
  const refundRef = db.doc(approval.targetAggregateRef);
  const refundSnap = await tx.get(refundRef);
  if (!refundSnap.exists) throw new HttpsError("not-found", "The refund request no longer exists.");
  const refund = refundSnap.data() as RefundRequestDoc;
  if (refund.version !== approval.targetAggregateVersion) {
    throw new HttpsError("failed-precondition", "The refund request has changed since this approval was created.");
  }
  if (refund.status !== "pendingApproval") {
    throw new HttpsError("failed-precondition", `Refund request is already "${refund.status}".`);
  }

  // Pass 1 (reads only). Firestore transactions require EVERY read across
  // the whole transaction to precede EVERY write — a per-allocation loop
  // that reads then writes inside the same iteration would already violate
  // that the moment a SECOND boncuk allocation appears in one mixed-tender
  // refund (e.g. two sub-accounts that each paid partly with Boncuk), even
  // though each individual iteration looks self-contained. Resolve every
  // boncuk allocation's lookups up front, before any write is issued.
  interface BoncukLookupResolved {
    kind: "resolved";
    customerId: string;
    accountRef: FirebaseFirestore.DocumentReference;
    account: FirebaseFirestore.DocumentData;
    rate: number;
    originalLedgerEntryId: string | null;
  }
  type BoncukLookup = { kind: "failed" } | BoncukLookupResolved;
  const boncukLookups = new Map<number, BoncukLookup>();

  for (let i = 0; i < refund.allocations.length; i++) {
    const alloc = refund.allocations[i];
    if (alloc.tenderType !== "boncuk") continue;
    const attemptSnap = await tx.get(db.collection(PAYMENT_ATTEMPTS_COLLECTION).doc(alloc.originalAttemptId));
    const attempt = attemptSnap.exists ? (attemptSnap.data() as PaymentAttemptDoc) : null;
    const subAccountId = attempt?.allocations[0]?.subAccountId;
    const subAccountSnap = subAccountId ? await tx.get(db.collection(GUEST_SUB_ACCOUNTS_COLLECTION).doc(subAccountId)) : null;
    const subAccount = subAccountSnap?.exists ? (subAccountSnap.data() as GuestSubAccountDoc) : null;
    const customerId = subAccount?.ownerAuthUid ?? null;
    if (!customerId) {
      boncukLookups.set(i, { kind: "failed" });
      continue;
    }
    const accountRef = db.collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${refund.organizationId}_${customerId}`);
    const accountSnap = await tx.get(accountRef);
    if (!accountSnap.exists) {
      boncukLookups.set(i, { kind: "failed" });
      continue;
    }
    // Restoration value -> Boncuk, using the SAME rate the original ledger
    // entry recorded (the inverse rate is not separately stored per-attempt
    // at this granularity in Wave A).
    const originalLedgerSnap = attempt?.loyaltyLedgerEntryId
      ? await tx.get(db.collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(attempt.loyaltyLedgerEntryId))
      : null;
    const rate = (originalLedgerSnap?.data()?.redemptionValueMinorUnitsPerBoncuk as number | undefined) ?? 1;
    boncukLookups.set(i, {
      kind: "resolved", customerId, accountRef, account: accountSnap.data()!, rate,
      originalLedgerEntryId: attempt?.loyaltyLedgerEntryId ?? null,
    });
  }

  // Pass 2 (writes only). Account-balance restorations are aggregated per
  // account (not written per-allocation) so that two boncuk allocations
  // touching the SAME customer's account within one refund never overwrite
  // each other using a stale pre-read balance.
  const accountRestorations = new Map<string, { accountRef: FirebaseFirestore.DocumentReference; account: FirebaseFirestore.DocumentData; totalRestored: number }>();
  const resolvedAllocations: RefundAllocationEntry[] = [];
  let anyFailed = false;
  for (let i = 0; i < refund.allocations.length; i++) {
    const alloc = refund.allocations[i];
    if (alloc.tenderType === "cash") {
      // Wave B will attach a real negative CashMovement here once cash
      // Firestore backing exists — disclosed, not fabricated (see this
      // file's own doc comment).
      resolvedAllocations.push({ ...alloc, status: "resolvedSucceeded" });
      continue;
    }
    if (alloc.tenderType === "boncuk") {
      const lookup = boncukLookups.get(i)!;
      if (lookup.kind === "failed") {
        resolvedAllocations.push({ ...alloc, status: "resolvedFailed" });
        anyFailed = true;
        continue;
      }
      const { customerId, accountRef, account, rate, originalLedgerEntryId } = lookup;
      const boncukRestored = Math.floor(alloc.amountMinorUnits / Math.max(rate, 1));
      const ledgerEntryId = deriveLoyaltyLedgerEntryId({ organizationId: refund.organizationId, customerId, entryType: "boncukRedemptionRestore", sourceId: `${approval.requestId}-${alloc.originalAttemptId}` });
      const ledgerEntry: LoyaltyLedgerEntry = {
        organizationId: refund.organizationId, customerId, entryType: "boncukRedemptionRestore",
        entitlementDeltaBoncuk: 0, spendableDeltaBoncuk: boncukRestored, debtDeltaBoncuk: 0,
        sourceId: approval.requestId, orderId: null,
        amountBasisMinorUnits: alloc.amountMinorUnits,
        earningCarryNumeratorBefore: null, earningCarryDenominatorBefore: null,
        earningCarryNumeratorAfter: null, earningCarryDenominatorAfter: null,
        earningSpendMinorUnits: null, earningBoncukAmount: null, loyaltyPolicyVersion: null,
        debtBeforeBoncuk: account.boncukDebt, debtAfterBoncuk: account.boncukDebt,
        redemptionValueMinorUnitsPerBoncuk: rate, maxRedemptionBasisPoints: null,
        idempotencyKey: `${approval.requestId}-${alloc.originalAttemptId}`, reversalOf: originalLedgerEntryId, expiresAt: null, metadata: null,
      } as LoyaltyLedgerEntry;
      tx.set(db.collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(ledgerEntryId), { ...ledgerEntry, createdAt: now });

      const existing = accountRestorations.get(accountRef.path);
      if (existing) {
        existing.totalRestored += boncukRestored;
      } else {
        accountRestorations.set(accountRef.path, { accountRef, account, totalRestored: boncukRestored });
      }
      resolvedAllocations.push({ ...alloc, status: "resolvedSucceeded", loyaltyLedgerEntryId: ledgerEntryId });
      continue;
    }
    // card | mealCard — certification-only fallback (no real provider configured).
    resolvedAllocations.push({ ...alloc, status: "resolvedSucceeded", providerRef: "certification-only-no-provider-configured" });
  }

  for (const { accountRef, account, totalRestored } of accountRestorations.values()) {
    tx.update(accountRef, { spendableBalance: account.spendableBalance + totalRestored, revision: account.revision + 1, updatedAt: now });
  }

  tx.update(refundRef, {
    status: anyFailed ? "failed" : "succeeded",
    allocations: resolvedAllocations,
    resolvedAt: now,
    version: refund.version + 1,
  });

  writeAuditEvent({
    tx, db, eventId: `${approval.requestId}-applied`,
    organizationId: refund.organizationId, branchId: refund.branchId,
    type: "paymentRefund.applied", targetRef: refundRef.path,
    newValue: { checkId: refund.checkId, amountMinorUnits: refund.amountMinorUnits },
    actorType: "staff", actorUid: respondedByActorUid,
    correlationId: `${approval.requestId}-audit`, clientRequestId: null, now,
  });

  return { newValue: { status: anyFailed ? "failed" : "succeeded" } };
}
