import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp, type Transaction, type Firestore } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { requireActiveDeviceSession } from "./trustedDevice";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";
import {
  CHECKS_COLLECTION,
  CHECK_ALLOCATIONS_COLLECTION,
  type CheckDoc,
} from "./checkAllocationConfig";
import { GUEST_SUB_ACCOUNTS_COLLECTION, type GuestSubAccountDoc } from "./tableSessionConfig";
import { LOYALTY_ACCOUNTS_COLLECTION, LOYALTY_LEDGER_ENTRIES_COLLECTION, deriveLoyaltyLedgerEntryId, type LoyaltyLedgerEntry } from "./loyaltyLedger";
import { resolveAccountForRedemption, calculateBoncukRedemption } from "./loyaltyRedemption";
import { loyaltyPolicyDocRef, loyaltyPolicyBootstrapRef, readLoyaltyPolicyInTransaction, writeDefaultLoyaltyPolicyInTransaction } from "./loyaltyPolicy";
import {
  PAYMENT_INTENTS_COLLECTION,
  PAYMENT_SESSIONS_COLLECTION,
  PAYMENT_ATTEMPTS_COLLECTION,
  BRANCH_PAYMENT_CONFIG_COLLECTION,
  sanitizeTenderType,
  computeCompletedSessionStatus,
  canTransitionPaymentAttempt,
  isAttemptSettled,
  computeServiceCharges,
  type PaymentSessionDoc,
  type PaymentIntentDoc,
  type PaymentAttemptDoc,
  type PaymentAllocationEntry,
  type BranchPaymentConfigDoc,
} from "./paymentDomain";
import { resolveProviderAdapter } from "./paymentProviderAdapter";

/**
 * AP-4 Wave A — the canonical, server-authoritative payment engine. Builds
 * directly on AP-3's real `checks`/`checkAllocations` (never a parallel
 * basket/total model) — see `paymentDomain.ts`'s own doc comment for the
 * full architectural framing.
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

interface StaffDeviceContext {
  organizationId: string;
  branchId: string;
  uid: string;
}

async function authorizePaymentCommand(request: CallableRequest, data: Record<string, unknown>): Promise<StaffDeviceContext> {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
  const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");
  requireStaffPermission(request, organizationId, "processPayments");
  requireBranchAccess(request, organizationId, branchId);
  await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);
  return { organizationId, branchId, uid: request.auth.uid };
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

// -----------------------------------------------------------------------
// createPaymentIntent — a frozen, re-verifiable snapshot of what's payable
// -----------------------------------------------------------------------

export const createPaymentIntent = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const { organizationId, branchId, uid } = await authorizePaymentCommand(request, data);
  const checkId = requireNonEmptyString(data.checkId, "checkId");
  const coverCount = typeof data.coverCount === "number" && Number.isInteger(data.coverCount) && data.coverCount >= 0 ? data.coverCount : 0;

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { data: check } = await loadCheckOrThrow(db, tx, checkId, organizationId, branchId);
    if (check.status !== "readyForPayment") {
      throw new HttpsError("failed-precondition", `Check must be "readyForPayment" to capture a payment intent (current: "${check.status}").`);
    }

    const intentId = `intent-${checkId}-v${check.version}`;
    const intentRef = db.collection(PAYMENT_INTENTS_COLLECTION).doc(intentId);
    const existingIntentSnap = await tx.get(intentRef);
    const sessionId = `session-${checkId}`;
    const sessionRef = db.collection(PAYMENT_SESSIONS_COLLECTION).doc(sessionId);

    if (existingIntentSnap.exists) {
      // Idempotent recapture for the SAME check version — never a new
      // intent, never a new session. Reuse both as-is.
      return { intentId, sessionId };
    }

    // Group active checkAllocations by subAccountId — the real, canonical
    // per-guest payable basis (never re-derived from raw order lines).
    const allocationsSnap = await tx.get(
      db.collection(CHECK_ALLOCATIONS_COLLECTION).where("checkId", "==", checkId).where("status", "==", "active"),
    );
    if (allocationsSnap.empty) {
      throw new HttpsError("failed-precondition", "Check has no active allocations — nothing is payable.");
    }
    const bySubAccount = new Map<string, number>();
    for (const doc of allocationsSnap.docs) {
      const amount = doc.data().allocatedAmountMinorUnits as number;
      const subAccountId = doc.data().subAccountId as string;
      bySubAccount.set(subAccountId, (bySubAccount.get(subAccountId) ?? 0) + amount);
    }
    const subAccountAllocations = [...bySubAccount.entries()].map(([subAccountId, payableAmountMinorUnits]) => ({
      subAccountId,
      payableAmountMinorUnits,
    }));
    const baseSubtotalMinorUnits = subAccountAllocations.reduce((sum, a) => sum + a.payableAmountMinorUnits, 0);

    const configRef = db.collection(BRANCH_PAYMENT_CONFIG_COLLECTION).doc(branchId);
    const configSnap = await tx.get(configRef);
    const config = configSnap.exists ? (configSnap.data() as BranchPaymentConfigDoc) : null;

    // Firestore transactions require every read to happen before any write —
    // read the (possibly pre-existing) session doc now, before `intentRef`
    // is written below, even though it's only acted on further down.
    const existingSessionSnap = await tx.get(sessionRef);

    const serviceCharges = computeServiceCharges({
      config,
      baseSubtotalMinorUnits,
      coverCount: coverCount || bySubAccount.size,
    });
    const payableAmountMinorUnits = baseSubtotalMinorUnits + serviceCharges.reduce((s, c) => s + c.amountMinorUnits, 0);

    const now = Timestamp.now();
    const intent: PaymentIntentDoc = {
      organizationId, branchId, checkId,
      checkVersionAtCapture: check.version,
      subAccountAllocations,
      payableAmountMinorUnits,
      serviceCharges,
      currencyCode: check.currencyCode,
      createdAt: now, createdByStaffUid: uid,
      supersededAt: null,
    };
    tx.set(intentRef, intent);

    if (!existingSessionSnap.exists) {
      const session: PaymentSessionDoc = {
        organizationId, branchId, checkId, intentId,
        status: "collecting",
        payableAmountMinorUnits, settledAmountMinorUnits: 0,
        currencyCode: check.currencyCode,
        cashTipMinorUnits: 0, cardTipMinorUnits: 0,
        createdAt: now, createdByStaffUid: uid, updatedAt: now,
        version: 1,
      };
      tx.set(sessionRef, session);
    } else {
      // A genuinely new intent for a check that already has a session means
      // the check changed before any payment activity started (the only way
      // `check.version` can advance is pre-`paymentActivityStarted`) —
      // repoint the still-`collecting` session at the fresh intent/amount.
      const existingSession = existingSessionSnap.data() as PaymentSessionDoc;
      if (existingSession.status !== "collecting") {
        throw new HttpsError("failed-precondition", "This check's payment session is no longer collecting — cannot recapture the intent.");
      }
      tx.update(sessionRef, { intentId, payableAmountMinorUnits, updatedAt: now, version: existingSession.version + 1 });
    }

    writeAuditEvent({
      tx, db, eventId: `${intentId}-created`,
      organizationId, branchId, type: "paymentIntent.created", targetRef: intentRef.path,
      newValue: { checkId, payableAmountMinorUnits },
      actorType: "staff", actorUid: uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });

    return { intentId, sessionId, payableAmountMinorUnits, subAccountAllocations, serviceCharges };
  });
});

// -----------------------------------------------------------------------
// recordPaymentAttempt — the one callable every tender type goes through
// -----------------------------------------------------------------------

function sumSettled(attempts: PaymentAttemptDoc[]): number {
  return attempts.filter((a) => isAttemptSettled(a.status)).reduce((s, a) => s + a.amountMinorUnits, 0);
}
function sumReserved(attempts: PaymentAttemptDoc[]): number {
  // Non-terminal-failed: reserved money a concurrent attempt must not double-spend.
  return attempts
    .filter((a) => a.status === "initiated" || a.status === "providerPending" || isAttemptSettled(a.status))
    .reduce((s, a) => s + a.amountMinorUnits, 0);
}

// Write-only — every read this needs (the full attempts list for the
// session) must already have happened earlier in the caller's transaction.
// Firestore transactions require ALL reads before ANY write, so this can
// never issue its own `tx.get` once the caller has started writing.
function finalizeSessionIfComplete(params: {
  tx: Transaction; sessionRef: FirebaseFirestore.DocumentReference; session: PaymentSessionDoc;
  checkRef: FirebaseFirestore.DocumentReference; now: Timestamp; attempts: PaymentAttemptDoc[];
}): void {
  const { tx, sessionRef, session, checkRef, now, attempts } = params;
  const settled = sumSettled(attempts);
  tx.update(sessionRef, { settledAmountMinorUnits: settled, updatedAt: now });
  if (settled >= session.payableAmountMinorUnits) {
    const completedStatus = computeCompletedSessionStatus(session.status);
    if (completedStatus === "completed") {
      tx.update(sessionRef, { status: "completed" });
      tx.update(checkRef, { status: "paid" });
    }
  }
}

export const recordPaymentAttempt = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const { organizationId, branchId, uid } = await authorizePaymentCommand(request, data);
  const checkId = requireNonEmptyString(data.checkId, "checkId");
  const sessionId = requireNonEmptyString(data.sessionId, "sessionId");
  const tenderType = sanitizeTenderType(data.tenderType);
  const idempotencyKey = requireNonEmptyString(data.idempotencyKey, "idempotencyKey");
  const rawAllocations = Array.isArray(data.allocations) ? (data.allocations as Array<Record<string, unknown>>) : [];
  if (rawAllocations.length === 0) invalid("allocations must be a non-empty array.");
  const requestedBoncukAmount = tenderType === "boncuk" ? requirePositiveInt(data.requestedBoncukAmount, "requestedBoncukAmount") : null;

  const db = getFirestore();
  const attemptId = db.collection(PAYMENT_ATTEMPTS_COLLECTION).doc().id;

  // Phase 1 (transactional): validate, resolve conservation, reserve the
  // amount, and resolve cash/boncuk SYNCHRONOUSLY (no external round-trip —
  // the cashier physically holds cash; Boncuk is fully internal). card/
  // mealCard stop at `providerPending` — the external call happens AFTER
  // this transaction commits, never inside it.
  const phase1 = await db.runTransaction(async (tx) => {
    const { ref: checkRef, data: check } = await loadCheckOrThrow(db, tx, checkId, organizationId, branchId);
    const sessionRef = db.collection(PAYMENT_SESSIONS_COLLECTION).doc(sessionId);
    const sessionSnap = await tx.get(sessionRef);
    if (!sessionSnap.exists) throw new HttpsError("not-found", "Payment session not found.");
    const session = sessionSnap.data() as PaymentSessionDoc;
    if (session.checkId !== checkId || session.organizationId !== organizationId || session.branchId !== branchId) {
      throw new HttpsError("not-found", "Payment session not found.");
    }
    // Idempotent replay — the SAME idempotencyKey scoped to this session
    // returns the original attempt untouched, never a duplicate charge.
    // Checked BEFORE the session-status guard below: a retry of the very
    // attempt that already completed the session (e.g. the cashier's client
    // resent the request after a dropped response) must still return the
    // original result, never a rejection.
    const existingByKeySnap = await tx.get(
      db.collection(PAYMENT_ATTEMPTS_COLLECTION).where("sessionId", "==", sessionId).where("idempotencyKey", "==", idempotencyKey),
    );
    if (!existingByKeySnap.empty) {
      const existing = existingByKeySnap.docs[0].data() as PaymentAttemptDoc;
      return { replay: true as const, attemptId: existingByKeySnap.docs[0].id, status: existing.status, tenderType: existing.tenderType };
    }

    // A genuinely NEW attempt (not a replay) is only ever accepted while the
    // session is still open for tenders.
    if (session.status !== "collecting" && session.status !== "readyToComplete") {
      throw new HttpsError("failed-precondition", `Payment session is "${session.status}" — no further tenders may be recorded.`);
    }

    const allocations: PaymentAllocationEntry[] = rawAllocations.map((a) => ({
      subAccountId: requireNonEmptyString(a.subAccountId, "allocations[].subAccountId"),
      orderLineRefs: Array.isArray(a.orderLineRefs) ? (a.orderLineRefs as string[]) : [],
      amountMinorUnits: requirePositiveInt(a.amountMinorUnits, "allocations[].amountMinorUnits"),
    }));
    if (tenderType === "boncuk" && allocations.length !== 1) {
      throw new HttpsError("invalid-argument", "A Boncuk payment must target exactly one sub-account.");
    }

    // Conservation, per the intent's own frozen per-subaccount payable
    // snapshot — the intent, not a fresh re-derivation, is the basis (an
    // underlying Check change after intent capture is impossible once
    // `paymentActivityStarted` — see paymentDomain.ts's doc comment).
    const intentRef = db.collection("paymentIntents").doc(session.intentId);
    const intentSnap = await tx.get(intentRef);
    if (!intentSnap.exists) throw new HttpsError("failed-precondition", "The payment intent no longer exists.");
    const intent = intentSnap.data() as PaymentIntentDoc;

    const existingAttemptsSnap = await tx.get(db.collection(PAYMENT_ATTEMPTS_COLLECTION).where("sessionId", "==", sessionId));
    const existingAttempts = existingAttemptsSnap.docs.map((d) => d.data() as PaymentAttemptDoc);

    for (const alloc of allocations) {
      const subAccountBasis = intent.subAccountAllocations.find((s) => s.subAccountId === alloc.subAccountId);
      if (!subAccountBasis) {
        throw new HttpsError("invalid-argument", `Sub-account "${alloc.subAccountId}" has no payable amount on this intent.`);
      }
      const reservedForThisSubAccount = existingAttempts
        .filter((a) => a.status === "initiated" || a.status === "providerPending" || isAttemptSettled(a.status))
        .flatMap((a) => a.allocations)
        .filter((a) => a.subAccountId === alloc.subAccountId)
        .reduce((s, a) => s + a.amountMinorUnits, 0);
      if (reservedForThisSubAccount + alloc.amountMinorUnits > subAccountBasis.payableAmountMinorUnits) {
        throw new HttpsError(
          "failed-precondition",
          `Amount exceeds sub-account "${alloc.subAccountId}"'s remaining payable balance.`,
          { code: "payment/exceeds-remaining" },
        );
      }
    }
    const totalReserved = sumReserved(existingAttempts);
    const requestedTotal = allocations.reduce((s, a) => s + a.amountMinorUnits, 0);
    if (totalReserved + requestedTotal > intent.payableAmountMinorUnits) {
      throw new HttpsError("failed-precondition", "Amount exceeds the check's remaining payable balance.", { code: "payment/exceeds-remaining" });
    }

    const now = Timestamp.now();
    const correlationId = generateCorrelationId();
    const attemptRef = db.collection(PAYMENT_ATTEMPTS_COLLECTION).doc(attemptId);
    const flagPaymentActivityStarted = !check.paymentActivityStarted;

    const baseAttempt: Omit<PaymentAttemptDoc, "status" | "amountMinorUnits" | "loyaltyLedgerEntryId" | "declineReason" | "resolvedAt" | "providerRef" | "providerResponseSummary"> = {
      organizationId, branchId, checkId, sessionId, intentId: session.intentId,
      tenderType, currencyCode: intent.currencyCode, allocations,
      idempotencyKey, createdAt: now, createdByStaffUid: uid, correlationId,
    };

    // Firestore transactions require every read across the WHOLE transaction
    // to happen before any write — so every tender branch below must finish
    // its own reads (if any) before this point is reached, and every write
    // (including the shared `paymentActivityStarted` flip) happens only
    // after that, immediately adjacent to the branch's own attempt write.

    if (tenderType === "cash") {
      const attempt: PaymentAttemptDoc = {
        ...baseAttempt, status: "succeeded", amountMinorUnits: requestedTotal,
        providerRef: null, providerResponseSummary: "Cash collected by staff.",
        loyaltyLedgerEntryId: null, declineReason: null, resolvedAt: now,
      };
      if (flagPaymentActivityStarted) tx.update(checkRef, { paymentActivityStarted: true });
      tx.set(attemptRef, attempt);
      finalizeSessionIfComplete({ tx, sessionRef, session, checkRef, now, attempts: [...existingAttempts, attempt] });
      return { replay: false as const, attemptId, status: "succeeded" as const, tenderType };
    }

    if (tenderType === "boncuk") {
      const subAccountId = allocations[0].subAccountId;
      const subAccountSnap = await tx.get(db.collection(GUEST_SUB_ACCOUNTS_COLLECTION).doc(subAccountId));
      if (!subAccountSnap.exists) throw new HttpsError("not-found", "Sub-account not found.");
      const subAccount = subAccountSnap.data() as GuestSubAccountDoc;
      if (subAccount.ownerAuthUid === null || subAccount.ownerType === "staffGeneral") {
        throw new HttpsError("failed-precondition", "Boncuk may only be spent by the sub-account's own owning customer, never a staff-general account.", { code: "payment/boncuk-not-eligible" });
      }
      const customerId = subAccount.ownerAuthUid;

      const accountRef = db.collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${customerId}`);
      const accountSnap = await tx.get(accountRef);
      const accountResult = resolveAccountForRedemption(accountSnap);

      // Only read the policy docs when an account actually exists to redeem
      // against — but this read must still happen before ANY write, so it
      // cannot be deferred past the `accountResult.status !== "ok"` branch's
      // own write below.
      const policyRef = loyaltyPolicyDocRef(db, organizationId);
      const bootstrapRef = loyaltyPolicyBootstrapRef(db, organizationId);
      const [policySnap, bootstrapSnap] = accountResult.status === "ok"
        ? await Promise.all([tx.get(policyRef), tx.get(bootstrapRef)])
        : [null, null];

      // All reads for this branch are now complete — writes only below.

      if (accountResult.status !== "ok") {
        const attempt: PaymentAttemptDoc = {
          ...baseAttempt, status: "declined", amountMinorUnits: requestedTotal,
          providerRef: null, providerResponseSummary: null, loyaltyLedgerEntryId: null,
          declineReason: "No Boncuk balance is available for this customer.", resolvedAt: now,
        };
        if (flagPaymentActivityStarted) tx.update(checkRef, { paymentActivityStarted: true });
        tx.set(attemptRef, attempt);
        return { replay: false as const, attemptId, status: "declined" as const, tenderType };
      }
      const account = accountResult.account;

      const policyResult = readLoyaltyPolicyInTransaction(policySnap!, bootstrapSnap!, organizationId, now);
      if (policyResult.status === "corrupt-policy-state" || policyResult.status === "missing-live-policy") {
        throw new HttpsError("failed-precondition", "Loyalty economics are temporarily unavailable for this organization.");
      }
      const policy = policyResult.policy;

      const subAccountBasis = intent.subAccountAllocations.find((s) => s.subAccountId === subAccountId)!;
      const calc = calculateBoncukRedemption({
        requestedBoncukAmount: requestedBoncukAmount!,
        spendableBalance: account.spendableBalance,
        grandTotalMinorUnits: subAccountBasis.payableAmountMinorUnits,
        boncukEligibleOrderAmountMinorUnits: subAccountBasis.payableAmountMinorUnits,
        redemptionValueMinorUnitsPerBoncuk: policy.redemptionValueMinorUnitsPerBoncuk,
        maxRedemptionBasisPoints: policy.maxRedemptionBasisPoints,
      });

      if (flagPaymentActivityStarted) tx.update(checkRef, { paymentActivityStarted: true });
      if (policyResult.needsProvisioning) {
        writeDefaultLoyaltyPolicyInTransaction(tx, db, policy);
      }

      if (calc.status !== "ok") {
        const attempt: PaymentAttemptDoc = {
          ...baseAttempt, status: "declined", amountMinorUnits: requestedTotal,
          providerRef: null, providerResponseSummary: null, loyaltyLedgerEntryId: null,
          declineReason: `Requested Boncuk exceeds the maximum usable amount (${calc.maxUsableBoncuk}).`, resolvedAt: now,
        };
        tx.set(attemptRef, attempt);
        return { replay: false as const, attemptId, status: "declined" as const, tenderType };
      }

      const ledgerEntryId = deriveLoyaltyLedgerEntryId({ organizationId, customerId, entryType: "boncukRedemption", sourceId: attemptId });
      const ledgerEntry: LoyaltyLedgerEntry = {
        organizationId, customerId, entryType: "boncukRedemption",
        entitlementDeltaBoncuk: 0, spendableDeltaBoncuk: 0 - calc.boncukUsed, debtDeltaBoncuk: 0,
        sourceId: attemptId, orderId: null,
        amountBasisMinorUnits: calc.valueMinorUnits,
        earningCarryNumeratorBefore: null, earningCarryDenominatorBefore: null,
        earningCarryNumeratorAfter: null, earningCarryDenominatorAfter: null,
        earningSpendMinorUnits: null, earningBoncukAmount: null,
        loyaltyPolicyVersion: policy.version,
        debtBeforeBoncuk: account.boncukDebt, debtAfterBoncuk: account.boncukDebt,
        redemptionValueMinorUnitsPerBoncuk: policy.redemptionValueMinorUnitsPerBoncuk,
        maxRedemptionBasisPoints: policy.maxRedemptionBasisPoints,
        idempotencyKey: attemptId, reversalOf: null, expiresAt: null, metadata: null,
      } as LoyaltyLedgerEntry;
      tx.set(db.collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(ledgerEntryId), { ...ledgerEntry, createdAt: now });
      tx.update(accountRef, {
        spendableBalance: account.spendableBalance - calc.boncukUsed,
        revision: account.revision + 1,
        updatedAt: now,
      });

      const attempt: PaymentAttemptDoc = {
        ...baseAttempt, status: "succeeded", amountMinorUnits: calc.valueMinorUnits,
        providerRef: null, providerResponseSummary: `${calc.boncukUsed} Boncuk redeemed.`,
        loyaltyLedgerEntryId: ledgerEntryId, declineReason: null, resolvedAt: now,
      };
      tx.set(attemptRef, attempt);
      finalizeSessionIfComplete({ tx, sessionRef, session, checkRef, now, attempts: [...existingAttempts, attempt] });
      return { replay: false as const, attemptId, status: "succeeded" as const, tenderType, boncukUsed: calc.boncukUsed };
    }

    // card | mealCard — reserve now, resolve outside this transaction.
    const attempt: PaymentAttemptDoc = {
      ...baseAttempt, status: "providerPending", amountMinorUnits: requestedTotal,
      providerRef: null, providerResponseSummary: null, loyaltyLedgerEntryId: null,
      declineReason: null, resolvedAt: null,
    };
    if (flagPaymentActivityStarted) tx.update(checkRef, { paymentActivityStarted: true });
    tx.set(attemptRef, attempt);
    return { replay: false as const, attemptId, status: "providerPending" as const, tenderType, amountMinorUnits: requestedTotal, currencyCode: intent.currencyCode };
  });

  if (phase1.replay || phase1.status !== "providerPending") {
    return phase1;
  }

  // Phase 2 (outside any transaction): the real external provider round-trip.
  const providerResult = await resolveProviderAdapter().charge({
    amountMinorUnits: (phase1 as { amountMinorUnits: number }).amountMinorUnits,
    currencyCode: (phase1 as { currencyCode: string }).currencyCode,
    idempotencyKey,
  });

  // Phase 3 (transactional): resolve the reserved attempt from the provider outcome.
  return db.runTransaction(async (tx) => {
    const attemptRef = db.collection(PAYMENT_ATTEMPTS_COLLECTION).doc(attemptId);
    const attemptSnap = await tx.get(attemptRef);
    if (!attemptSnap.exists) throw new HttpsError("internal", "Payment attempt disappeared between reservation and resolution.");
    const attempt = attemptSnap.data() as PaymentAttemptDoc;
    if (attempt.status !== "providerPending") {
      // Already resolved (e.g. a racing retry) — idempotent early return.
      return { replay: true as const, attemptId, status: attempt.status, tenderType: attempt.tenderType };
    }
    const now = Timestamp.now();
    const sessionRef = db.collection(PAYMENT_SESSIONS_COLLECTION).doc(sessionId);
    const sessionSnap = await tx.get(sessionRef);
    const session = sessionSnap.data() as PaymentSessionDoc;
    const checkRef = db.collection(CHECKS_COLLECTION).doc(checkId);

    let nextStatus: PaymentAttemptDoc["status"];
    let update: Partial<PaymentAttemptDoc>;
    if (providerResult.outcome === "succeeded") {
      nextStatus = "succeeded";
      update = { status: nextStatus, providerRef: providerResult.providerRef, providerResponseSummary: providerResult.responseSummary, resolvedAt: now };
    } else if (providerResult.outcome === "declined") {
      nextStatus = "declined";
      update = { status: nextStatus, declineReason: providerResult.declineReason, resolvedAt: now };
    } else {
      nextStatus = "timedOut";
      update = { status: nextStatus, resolvedAt: now };
    }
    if (!canTransitionPaymentAttempt(attempt.status, nextStatus)) {
      throw new HttpsError("internal", `Invalid payment attempt transition "${attempt.status}" -> "${nextStatus}".`);
    }

    // Read (not write) the rest of the session's attempts BEFORE any write,
    // only when this resolution could complete the session — merging in
    // this attempt's about-to-be-written update since Firestore hasn't
    // seen it yet.
    let attemptsForFinalize: PaymentAttemptDoc[] | null = null;
    if (nextStatus === "succeeded") {
      const attemptsSnap = await tx.get(db.collection(PAYMENT_ATTEMPTS_COLLECTION).where("sessionId", "==", sessionId));
      attemptsForFinalize = attemptsSnap.docs.map((d) =>
        d.id === attemptId ? { ...(d.data() as PaymentAttemptDoc), ...update } : (d.data() as PaymentAttemptDoc),
      );
    }

    tx.update(attemptRef, update);

    if (nextStatus === "succeeded" && attemptsForFinalize) {
      finalizeSessionIfComplete({ tx, sessionRef, session, checkRef, now, attempts: attemptsForFinalize });
    }

    return { replay: false as const, attemptId, status: nextStatus, tenderType: attempt.tenderType };
  });
});
