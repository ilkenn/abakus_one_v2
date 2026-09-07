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
import { CHECKS_COLLECTION, CHECK_ALLOCATIONS_COLLECTION, CHECK_FINANCIAL_ADJUSTMENTS_COLLECTION } from "./checkAllocationConfig";
import type { CheckDoc, CheckAllocationDoc } from "./checkAllocationConfig";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  deriveLoyaltyLedgerEntryId,
  type LoyaltyLedgerEntry,
} from "./loyaltyLedger";
import type { LoyaltyAccountData } from "./getCustomerLoyaltySnapshot";
import { prepareCancellationStockHandling, applyCancellationStockHandling } from "./cancelOrderLineStock";

/**
 * AP-3 Wave 2C/2D — asynchronous, remote-approval-gated typed actions
 * (corrected report §3/§4, Stage B mandatory refinements #5/#9). Every
 * action here follows the SAME asynchronous shape `deviceActivation`
 * already proved (`remoteApproval.ts`): request -> pending -> an eligible
 * responder approves/rejects -> the closed typed handler re-verifies the
 * target's current version and applies the action exactly once. No
 * Function here ever blocks waiting for a manager, and no provisional
 * financial effect is ever applied before approval.
 *
 * **Financial adjustments stay structurally separate from the Boncuk
 * ledger** — `requestCheckFinancialAdjustment` never touches
 * `loyaltyLedgerEntries`/`loyaltyAccounts`, and `requestBoncukBalanceCorrection`
 * never touches `checks`/`checkAllocations`/`checkFinancialAdjustments`.
 * Only the latter may ever write a loyalty `adminAdjustment` entry.
 */

function invalid(message: string): never {
  throw new HttpsError("invalid-argument", message);
}
function requireNonEmptyString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.length === 0) invalid(`${field} is required.`);
  return raw as string;
}

// -----------------------------------------------------------------------
// Check Financial Adjustment
// -----------------------------------------------------------------------

type AdjustmentType = "complimentary" | "percentage" | "fixedAmount";
type AdjustmentScope = "product" | "subAccount" | "check";

interface CheckFinancialAdjustmentDoc {
  checkId: string;
  organizationId: string;
  branchId: string;
  scope: AdjustmentScope;
  scopeRef: { allocationId: string | null; subAccountId: string | null };
  adjustmentType: AdjustmentType;
  percentageBasisPoints: number | null;
  fixedAmountMinorUnits: number | null;
  /** Snapshotted at REQUEST time for display/audit only — the actual applied amount is always recomputed fresh, live, inside the approval handler's own transaction (never trusted stale). */
  requestedAppliedAmountMinorUnits: number;
  appliedAmountMinorUnits: number | null;
  currencyCode: string;
  reasonCode: string;
  reasonMessage: string;
  approvalRequestRef: string;
  requestedByStaffUid: string;
  status: "pendingApproval" | "active" | "rejected" | "reversed";
  reversalOf: string | null;
  calculationSnapshot: { baseAmountMinorUnits: number; policyVersion: string };
  createdAt: Timestamp;
  version: number;
}

const POLICY_VERSION = "AP3-W2C-v1";

/** Basis-points percentage math, floor-rounded, minor units — never a floating-point percentage. */
function computePercentageAmount(baseAmountMinorUnits: number, percentageBasisPoints: number): number {
  return Math.floor((baseAmountMinorUnits * percentageBasisPoints) / 10_000);
}

function requireValidAdjustmentType(
  adjustmentType: unknown,
  percentageBasisPoints: unknown,
  fixedAmountMinorUnits: unknown,
): { adjustmentType: AdjustmentType; percentageBasisPoints: number | null; fixedAmountMinorUnits: number | null } {
  if (adjustmentType === "complimentary") {
    return { adjustmentType, percentageBasisPoints: null, fixedAmountMinorUnits: null };
  }
  if (adjustmentType === "percentage") {
    if (typeof percentageBasisPoints !== "number" || !Number.isInteger(percentageBasisPoints) || percentageBasisPoints <= 0 || percentageBasisPoints > 10_000) {
      invalid("percentageBasisPoints must be an integer in (0, 10000].");
    }
    return { adjustmentType, percentageBasisPoints: percentageBasisPoints as number, fixedAmountMinorUnits: null };
  }
  if (adjustmentType === "fixedAmount") {
    if (typeof fixedAmountMinorUnits !== "number" || !Number.isInteger(fixedAmountMinorUnits) || fixedAmountMinorUnits <= 0) {
      invalid("fixedAmountMinorUnits must be a positive integer.");
    }
    return { adjustmentType, percentageBasisPoints: null, fixedAmountMinorUnits: fixedAmountMinorUnits as number };
  }
  invalid('adjustmentType must be "complimentary", "percentage", or "fixedAmount".');
}

export const requestCheckFinancialAdjustment = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
  const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");
  const checkId = requireNonEmptyString(data.checkId, "checkId");
  const scope = data.scope as AdjustmentScope;
  if (scope !== "product" && scope !== "subAccount" && scope !== "check") invalid('scope must be "product", "subAccount", or "check".');
  const allocationId = scope === "product" ? requireNonEmptyString(data.allocationId, "allocationId") : null;
  const subAccountId = scope === "subAccount" ? requireNonEmptyString(data.subAccountId, "subAccountId") : null;
  const { adjustmentType, percentageBasisPoints, fixedAmountMinorUnits } = requireValidAdjustmentType(
    data.adjustmentType, data.percentageBasisPoints, data.fixedAmountMinorUnits,
  );
  const reasonCode = requireNonEmptyString(data.reasonCode, "reasonCode");
  const reasonMessage = requireNonEmptyString(data.reasonMessage, "reasonMessage");

  requireStaffPermission(request, organizationId, "manageDineInOrders");
  requireBranchAccess(request, organizationId, branchId);
  await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const checkRef = db.collection(CHECKS_COLLECTION).doc(checkId);
    const checkSnap = await tx.get(checkRef);
    if (!checkSnap.exists) throw new HttpsError("not-found", "Check not found.");
    const check = checkSnap.data() as CheckDoc;
    if (check.organizationId !== organizationId || check.branchId !== branchId) {
      throw new HttpsError("not-found", "Check not found.");
    }
    if (check.status === "cancelled") throw new HttpsError("failed-precondition", "This check is cancelled.");

    let baseAmountMinorUnits: number;
    if (scope === "check") {
      baseAmountMinorUnits = check.computedTotalMinorUnits;
    } else if (scope === "product") {
      const allocSnap = await tx.get(db.collection(CHECK_ALLOCATIONS_COLLECTION).doc(allocationId!));
      if (!allocSnap.exists || (allocSnap.data() as CheckAllocationDoc).status !== "active" || (allocSnap.data() as CheckAllocationDoc).checkId !== checkId) {
        throw new HttpsError("not-found", "The referenced allocation is not active on this check.");
      }
      baseAmountMinorUnits = (allocSnap.data() as CheckAllocationDoc).allocatedAmountMinorUnits;
    } else {
      const subSnap = await tx.get(
        db.collection(CHECK_ALLOCATIONS_COLLECTION).where("checkId", "==", checkId).where("status", "==", "active").where("subAccountId", "==", subAccountId),
      );
      baseAmountMinorUnits = subSnap.docs.reduce((s, d) => s + (d.data().allocatedAmountMinorUnits as number), 0);
      if (baseAmountMinorUnits === 0) throw new HttpsError("failed-precondition", "This sub-account has no active allocations on this check.");
    }

    let requestedAppliedAmountMinorUnits: number;
    if (adjustmentType === "complimentary") requestedAppliedAmountMinorUnits = baseAmountMinorUnits;
    else if (adjustmentType === "percentage") requestedAppliedAmountMinorUnits = computePercentageAmount(baseAmountMinorUnits, percentageBasisPoints!);
    else requestedAppliedAmountMinorUnits = Math.min(fixedAmountMinorUnits!, baseAmountMinorUnits);

    const adjustmentRef = db.collection(CHECK_FINANCIAL_ADJUSTMENTS_COLLECTION).doc();
    const now = Timestamp.now();
    const doc: CheckFinancialAdjustmentDoc = {
      checkId, organizationId, branchId, scope,
      scopeRef: { allocationId, subAccountId },
      adjustmentType, percentageBasisPoints, fixedAmountMinorUnits,
      requestedAppliedAmountMinorUnits, appliedAmountMinorUnits: null,
      currencyCode: check.currencyCode,
      reasonCode, reasonMessage,
      approvalRequestRef: "", // set below, same transaction
      requestedByStaffUid: request.auth!.uid,
      status: "pendingApproval",
      reversalOf: null,
      calculationSnapshot: { baseAmountMinorUnits, policyVersion: POLICY_VERSION },
      createdAt: now,
      version: 1,
    };
    tx.set(adjustmentRef, doc);

    const approval = await createApprovalRequest({
      organizationId, branchId, actionType: "checkFinancialAdjustment",
      requestedByActorUid: request.auth!.uid, targetAggregateRef: adjustmentRef.path, targetAggregateVersion: 1,
      payloadHash: `${adjustmentType}-${requestedAppliedAmountMinorUnits}`,
    });
    tx.update(adjustmentRef, { approvalRequestRef: approval.requestId });

    writeAuditEvent({
      tx, db, eventId: `${adjustmentRef.id}-requested`, organizationId, branchId,
      type: "checkFinancialAdjustment.requested", targetRef: adjustmentRef.path,
      newValue: { scope, adjustmentType, requestedAppliedAmountMinorUnits },
      actorType: "staff", actorUid: request.auth!.uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });

    return { adjustmentId: adjustmentRef.id, approvalRequestId: approval.requestId, requestedAppliedAmountMinorUnits };
  });
});

/** The allowlisted `checkFinancialAdjustment` handler — called only from `remoteApproval.ts`'s own transaction. Recomputes the applied amount FRESH, live, against the check's current state — never trusts the request-time snapshot for the actual monetary effect (Stage B mandatory refinement #9: "never exceed eligible remaining value", checked against LIVE state, not a stale one). */
export async function applyCheckFinancialAdjustment(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, request: approval } = params;
  const adjustmentRef = db.doc(approval.targetAggregateRef);
  const adjustmentSnap = await tx.get(adjustmentRef);
  if (!adjustmentSnap.exists) throw new HttpsError("not-found", "The financial adjustment no longer exists.");
  const adjustment = adjustmentSnap.data() as CheckFinancialAdjustmentDoc;
  if (adjustment.version !== approval.targetAggregateVersion) {
    throw new HttpsError("failed-precondition", "The adjustment has changed since this approval request was created.");
  }
  if (adjustment.status !== "pendingApproval") {
    throw new HttpsError("failed-precondition", `Adjustment is already "${adjustment.status}" — cannot apply.`);
  }

  const checkRef = db.collection(CHECKS_COLLECTION).doc(adjustment.checkId);
  const checkSnap = await tx.get(checkRef);
  if (!checkSnap.exists) throw new HttpsError("not-found", "The check no longer exists.");
  const check = checkSnap.data() as CheckDoc;
  if (check.status === "cancelled") throw new HttpsError("failed-precondition", "The check has been cancelled since this request was made.");

  let liveBaseAmountMinorUnits: number;
  if (adjustment.scope === "check") {
    liveBaseAmountMinorUnits = check.computedTotalMinorUnits;
  } else if (adjustment.scope === "product") {
    const allocSnap = await tx.get(db.collection(CHECK_ALLOCATIONS_COLLECTION).doc(adjustment.scopeRef.allocationId!));
    liveBaseAmountMinorUnits = allocSnap.exists && (allocSnap.data() as CheckAllocationDoc).status === "active"
      ? (allocSnap.data() as CheckAllocationDoc).allocatedAmountMinorUnits : 0;
  } else {
    const subSnap = await tx.get(
      db.collection(CHECK_ALLOCATIONS_COLLECTION).where("checkId", "==", adjustment.checkId).where("status", "==", "active").where("subAccountId", "==", adjustment.scopeRef.subAccountId),
    );
    liveBaseAmountMinorUnits = subSnap.docs.reduce((s, d) => s + (d.data().allocatedAmountMinorUnits as number), 0);
  }

  let appliedAmountMinorUnits: number;
  if (adjustment.adjustmentType === "complimentary") appliedAmountMinorUnits = liveBaseAmountMinorUnits;
  else if (adjustment.adjustmentType === "percentage") appliedAmountMinorUnits = computePercentageAmount(liveBaseAmountMinorUnits, adjustment.percentageBasisPoints!);
  else appliedAmountMinorUnits = Math.min(adjustment.fixedAmountMinorUnits!, liveBaseAmountMinorUnits);
  // Never reduce the check's total below zero, regardless of scope.
  appliedAmountMinorUnits = Math.min(appliedAmountMinorUnits, check.computedTotalMinorUnits);
  appliedAmountMinorUnits = Math.max(appliedAmountMinorUnits, 0);

  tx.update(checkRef, { computedTotalMinorUnits: check.computedTotalMinorUnits - appliedAmountMinorUnits, version: check.version + 1 });
  tx.update(adjustmentRef, { status: "active", appliedAmountMinorUnits, version: adjustment.version + 1 });

  return { newValue: { appliedAmountMinorUnits } };
}

/** Manager+ (`approveCheckFinancialAdjustment`) — reverses an already-applied adjustment via a NEW immutable compensating record, never by editing the original (Stage B mandatory refinement #9: "reversal is a new immutable compensating record, never destructive editing"). Immediate, not itself approval-gated — a manager exercising this permission already carries the required authority. */
export const reverseCheckFinancialAdjustment = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
  const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");
  const adjustmentId = requireNonEmptyString(data.adjustmentId, "adjustmentId");

  requireStaffPermission(request, organizationId, "approveCheckFinancialAdjustment");
  requireBranchAccess(request, organizationId, branchId);
  await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const originalRef = db.collection(CHECK_FINANCIAL_ADJUSTMENTS_COLLECTION).doc(adjustmentId);
    const originalSnap = await tx.get(originalRef);
    if (!originalSnap.exists) throw new HttpsError("not-found", "Adjustment not found.");
    const original = originalSnap.data() as CheckFinancialAdjustmentDoc;
    if (original.organizationId !== organizationId || original.branchId !== branchId) throw new HttpsError("not-found", "Adjustment not found.");
    if (original.status !== "active") throw new HttpsError("failed-precondition", "Only an active adjustment may be reversed.");

    const checkRef = db.collection(CHECKS_COLLECTION).doc(original.checkId);
    const checkSnap = await tx.get(checkRef);
    if (!checkSnap.exists) throw new HttpsError("not-found", "Check not found.");
    const check = checkSnap.data() as CheckDoc;

    const now = Timestamp.now();
    tx.update(originalRef, { status: "reversed", version: original.version + 1 });
    tx.update(checkRef, { computedTotalMinorUnits: check.computedTotalMinorUnits + (original.appliedAmountMinorUnits ?? 0), version: check.version + 1 });

    const reversalRef = db.collection(CHECK_FINANCIAL_ADJUSTMENTS_COLLECTION).doc();
    const reversal: CheckFinancialAdjustmentDoc = {
      ...original,
      requestedAppliedAmountMinorUnits: original.appliedAmountMinorUnits ?? 0,
      appliedAmountMinorUnits: -(original.appliedAmountMinorUnits ?? 0),
      status: "active",
      reversalOf: adjustmentId,
      approvalRequestRef: "",
      requestedByStaffUid: request.auth!.uid,
      createdAt: now,
      version: 1,
    };
    tx.set(reversalRef, reversal);

    writeAuditEvent({
      tx, db, eventId: `${adjustmentId}-reversed`, organizationId, branchId,
      type: "checkFinancialAdjustment.reversed", targetRef: originalRef.path,
      newValue: { reversalId: reversalRef.id, restoredAmountMinorUnits: original.appliedAmountMinorUnits },
      actorType: "staff", actorUid: request.auth!.uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });

    return { reversalId: reversalRef.id };
  });
});

// -----------------------------------------------------------------------
// Accepted-line cancellation (Wave 2D)
// -----------------------------------------------------------------------

interface AcceptedLineCancellationRequestDoc {
  orderId: string;
  lineIndex: number;
  organizationId: string;
  branchId: string;
  requestedByStaffUid: string;
  reasonCode: string;
  reasonMessage: string;
  approvalRequestRef: string;
  status: "pendingApproval" | "applied" | "rejected";
  createdAt: Timestamp;
  version: number;
}

export const requestAcceptedLineCancellation = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
  const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");
  const orderId = requireNonEmptyString(data.orderId, "orderId");
  if (typeof data.lineIndex !== "number" || !Number.isInteger(data.lineIndex) || data.lineIndex < 0) invalid("lineIndex must be a non-negative integer.");
  const lineIndex = data.lineIndex as number;
  const reasonCode = requireNonEmptyString(data.reasonCode, "reasonCode");
  const reasonMessage = requireNonEmptyString(data.reasonMessage, "reasonMessage");

  requireStaffPermission(request, organizationId, "manageDineInOrders");
  requireBranchAccess(request, organizationId, branchId);
  await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const orderRef = db.collection("orders").doc(orderId);
    const orderSnap = await tx.get(orderRef);
    if (!orderSnap.exists) throw new HttpsError("not-found", "Order not found.");
    const order = orderSnap.data()!;
    if (order.organizationId !== organizationId || order.branchId !== branchId) throw new HttpsError("not-found", "Order not found.");
    const lines = (order.lines ?? []) as Array<{ status: string }>;
    if (lineIndex >= lines.length) throw new HttpsError("invalid-argument", "lineIndex is out of range.");
    if (lines[lineIndex].status !== "accepted") {
      throw new HttpsError("failed-precondition", `Line ${lineIndex} is not accepted (current status: ${lines[lineIndex].status}) — only an accepted line may be cancelled through this flow.`);
    }

    const requestRef = db.collection("acceptedLineCancellationRequests").doc(`${orderId}_${lineIndex}_${Date.now()}`);
    const now = Timestamp.now();
    const doc: AcceptedLineCancellationRequestDoc = {
      orderId, lineIndex, organizationId, branchId,
      requestedByStaffUid: request.auth!.uid, reasonCode, reasonMessage,
      approvalRequestRef: "", status: "pendingApproval", createdAt: now, version: 1,
    };
    tx.set(requestRef, doc);

    const approval = await createApprovalRequest({
      organizationId, branchId, actionType: "acceptedLineCancellation",
      requestedByActorUid: request.auth!.uid, targetAggregateRef: requestRef.path, targetAggregateVersion: 1,
      payloadHash: `${orderId}-${lineIndex}`,
    });
    tx.update(requestRef, { approvalRequestRef: approval.requestId });

    return { cancellationRequestId: requestRef.id, approvalRequestId: approval.requestId };
  });
});

/** The allowlisted `acceptedLineCancellation` handler. Voids the line (`cancelledAfterAcceptance`), records full provenance on the order line itself, and emits an idempotent downstream event describing whether preparation had started (AP-5's own future consumer — this handler only produces the signal, never AP-5's stock/KDS behavior itself). */
export async function applyAcceptedLineCancellation(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, request: approval, now, respondedByActorUid } = params;
  const requestRef = db.doc(approval.targetAggregateRef);
  const requestSnap = await tx.get(requestRef);
  if (!requestSnap.exists) throw new HttpsError("not-found", "The cancellation request no longer exists.");
  const cancellationRequest = requestSnap.data() as AcceptedLineCancellationRequestDoc;
  if (cancellationRequest.version !== approval.targetAggregateVersion) {
    throw new HttpsError("failed-precondition", "The cancellation request has changed since this approval was created.");
  }
  if (cancellationRequest.status !== "pendingApproval") {
    throw new HttpsError("failed-precondition", `Cancellation request is already "${cancellationRequest.status}".`);
  }

  const orderRef = db.collection("orders").doc(cancellationRequest.orderId);
  const orderSnap = await tx.get(orderRef);
  if (!orderSnap.exists) throw new HttpsError("not-found", "The order no longer exists.");
  const order = orderSnap.data()!;
  const lines = [...(order.lines ?? [])] as Array<Record<string, unknown>>;
  const line = lines[cancellationRequest.lineIndex];
  if (!line || line.status !== "accepted") {
    throw new HttpsError("failed-precondition", "This line is no longer in the accepted state — cannot cancel.");
  }

  // Preparation-started signal — best-effort from the order's own current
  // lifecycle status (Wave 2 has no dedicated per-line KDS "fired" signal
  // yet; `preparing`-or-later is the honest, disclosed proxy available
  // this phase). AP-5 owns building a real per-line signal.
  const preparationStarted = ["preparing", "ready", "served", "completed"].includes(String(order.status));

  // AP-5 Sprint 3 — the real consumer this handler's own doc comment
  // forecast. Read phase must run BEFORE this function's first write
  // (`tx.update(orderRef, ...)` below), per this codebase's own
  // Firestore-transaction discipline. Uses the real per-line
  // `kitchenWorkItem` status, not the `preparationStarted` proxy above
  // (kept only for `orderLineCancellationEvents`' own existing shape).
  const orderLineId = `kt-${cancellationRequest.orderId}-line-${cancellationRequest.lineIndex}`;
  const stockPlan = await prepareCancellationStockHandling({
    tx,
    db,
    organizationId: cancellationRequest.organizationId,
    branchId: cancellationRequest.branchId,
    orderId: cancellationRequest.orderId,
    orderLineIds: [orderLineId],
    performedByUid: respondedByActorUid,
    now,
  });

  lines[cancellationRequest.lineIndex] = {
    ...line,
    status: "cancelledAfterAcceptance",
    cancellation: {
      originalStatus: "accepted",
      requestedByStaffUid: cancellationRequest.requestedByStaffUid,
      approvedByStaffUid: respondedByActorUid,
      reasonCode: cancellationRequest.reasonCode,
      reasonMessage: cancellationRequest.reasonMessage,
      approvalRequestRef: approval.requestId,
      cancelledAt: now.toDate().toISOString(),
    },
  };
  tx.update(orderRef, { lines });
  tx.update(requestRef, { status: "applied", version: cancellationRequest.version + 1 });
  applyCancellationStockHandling(tx, db, stockPlan);

  // Idempotent downstream event — deterministic id, `.set()` not `.create()`
  // (mirrors `reservationEvents.ts`'s own "no retrigger source, no
  // ambiguity about a second real occurrence" reasoning) so a duplicate
  // handler invocation for the SAME approval can never double-emit.
  const eventRef = db.collection("orderLineCancellationEvents").doc(`${cancellationRequest.orderId}_${cancellationRequest.lineIndex}`);
  tx.set(eventRef, {
    orderId: cancellationRequest.orderId,
    lineIndex: cancellationRequest.lineIndex,
    organizationId: cancellationRequest.organizationId,
    branchId: cancellationRequest.branchId,
    preparationStarted,
    approvalRequestRef: approval.requestId,
    recordedAt: now,
    // AP-5 Sprint 3 — this handler IS the consumer this field was always
    // meant for; processed inline, so this is set true immediately, never
    // left for a separate sweep to pick up.
    consumedByStockReconciliation: true,
  });

  return { newValue: { lineIndex: cancellationRequest.lineIndex, preparationStarted } };
}

// -----------------------------------------------------------------------
// Boncuk balance correction (loyalty-only, structurally separate)
// -----------------------------------------------------------------------

interface BoncukBalanceCorrectionRequestDoc {
  organizationId: string;
  customerId: string;
  deltaBoncuk: number;
  reasonCode: string;
  reasonMessage: string;
  requestedByStaffUid: string;
  approvalRequestRef: string;
  status: "pendingApproval" | "applied" | "rejected";
  createdAt: Timestamp;
  version: number;
}

export const requestBoncukBalanceCorrection = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const customerId = requireNonEmptyString(data.customerId, "customerId");
  if (typeof data.deltaBoncuk !== "number" || !Number.isInteger(data.deltaBoncuk) || data.deltaBoncuk === 0) {
    invalid("deltaBoncuk must be a non-zero integer.");
  }
  const deltaBoncuk = data.deltaBoncuk as number;
  const reasonCode = requireNonEmptyString(data.reasonCode, "reasonCode");
  const reasonMessage = requireNonEmptyString(data.reasonMessage, "reasonMessage");

  // Loyalty balance corrections are an organization-level (not branch-
  // scoped) financial-exception action — `approveBoncukBalanceCorrection`
  // is checked directly, mirroring `manageStaffAccounts`'s own org-only
  // (no `requireBranchAccess`) shape.
  requireStaffPermission(request, organizationId, "manageDineInOrders");

  const db = getFirestore();
  const requestId = `boncuk-correction-${organizationId}-${customerId}-${Date.now()}`;
  const requestRef = db.collection("boncukBalanceCorrectionRequests").doc(requestId);
  const now = Timestamp.now();
  const doc: BoncukBalanceCorrectionRequestDoc = {
    organizationId, customerId, deltaBoncuk, reasonCode, reasonMessage,
    requestedByStaffUid: request.auth.uid, approvalRequestRef: "", status: "pendingApproval", createdAt: now, version: 1,
  };
  await requestRef.set(doc);
  const approval = await createApprovalRequest({
    organizationId, branchId: "platform", actionType: "boncukBalanceCorrection",
    requestedByActorUid: request.auth.uid, targetAggregateRef: requestRef.path, targetAggregateVersion: 1,
    payloadHash: `${customerId}-${deltaBoncuk}`,
  });
  await requestRef.update({ approvalRequestRef: approval.requestId });
  return { correctionRequestId: requestId, approvalRequestId: approval.requestId };
});

/** The allowlisted `boncukBalanceCorrection` handler — the ONLY writer of a genuine Boncuk balance-correction `adminAdjustment` ledger entry (Stage B mandatory refinement #9: "Only actual Boncuk balance correction may write loyalty adminAdjustment"). Structurally cannot be reached from any check/allocation code path. */
export async function applyBoncukBalanceCorrection(params: ActionHandlerParams): Promise<ActionHandlerResult> {
  const { tx, db, request: approval, now, respondedByActorUid } = params;
  const requestRef = db.doc(approval.targetAggregateRef);
  const requestSnap = await tx.get(requestRef);
  if (!requestSnap.exists) throw new HttpsError("not-found", "The correction request no longer exists.");
  const correctionRequest = requestSnap.data() as BoncukBalanceCorrectionRequestDoc;
  if (correctionRequest.version !== approval.targetAggregateVersion) {
    throw new HttpsError("failed-precondition", "The correction request has changed since this approval was created.");
  }
  if (correctionRequest.status !== "pendingApproval") {
    throw new HttpsError("failed-precondition", `Correction request is already "${correctionRequest.status}".`);
  }

  const accountRef = db.collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${correctionRequest.organizationId}_${correctionRequest.customerId}`);
  const accountSnap = await tx.get(accountRef);
  if (!accountSnap.exists) throw new HttpsError("failed-precondition", "No loyalty account exists for this customer.");
  const account = accountSnap.data() as LoyaltyAccountData;

  const ledgerEntryId = deriveLoyaltyLedgerEntryId({
    organizationId: correctionRequest.organizationId, customerId: correctionRequest.customerId,
    entryType: "adminAdjustment", sourceId: approval.requestId,
  });
  const ledgerEntry: LoyaltyLedgerEntry = {
    organizationId: correctionRequest.organizationId, customerId: correctionRequest.customerId,
    entryType: "adminAdjustment",
    entitlementDeltaBoncuk: 0,
    spendableDeltaBoncuk: correctionRequest.deltaBoncuk,
    debtDeltaBoncuk: 0,
    sourceId: approval.requestId, orderId: null,
    amountBasisMinorUnits: null,
    earningCarryNumeratorBefore: null, earningCarryDenominatorBefore: null,
    earningCarryNumeratorAfter: null, earningCarryDenominatorAfter: null,
    earningSpendMinorUnits: null, earningBoncukAmount: null, loyaltyPolicyVersion: null,
    debtBeforeBoncuk: account.boncukDebt, debtAfterBoncuk: account.boncukDebt,
    redemptionValueMinorUnitsPerBoncuk: null, maxRedemptionBasisPoints: null,
    idempotencyKey: approval.requestId, reversalOf: null, expiresAt: null,
    metadata: { entryType: "adminAdjustment", staffActorId: respondedByActorUid, reason: correctionRequest.reasonMessage },
  } as LoyaltyLedgerEntry;

  tx.set(db.collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(ledgerEntryId), { ...ledgerEntry, createdAt: now });
  tx.set(accountRef, {
    ...account,
    spendableBalance: account.spendableBalance + correctionRequest.deltaBoncuk,
    revision: (account as unknown as { revision: number }).revision + 1,
    updatedAt: now,
  });
  tx.update(requestRef, { status: "applied", version: correctionRequest.version + 1 });

  return { newValue: { deltaBoncuk: correctionRequest.deltaBoncuk } };
}
