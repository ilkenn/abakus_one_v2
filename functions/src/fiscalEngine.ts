import { onCall, HttpsError } from "firebase-functions/v2/https";
import type { CallableRequest } from "firebase-functions/v2/https";
import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { requireStaffPermission, requireBranchAccess } from "./staffAuthorization";
import { requireActiveDeviceSession } from "./trustedDevice";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId, sanitizeClientRequestId } from "./correlationId";
import { resolveFiscalAdapter } from "./fiscalAdapter";
import { CASH_SESSIONS_COLLECTION, computeBusinessDate } from "./cashDomain";
import { BRANCH_PAYMENT_CONFIG_COLLECTION, type BranchPaymentConfigDoc } from "./paymentDomain";
import {
  FISCAL_OPERATION_JOURNAL_COLLECTION,
  OFFLINE_LEASES_COLLECTION,
  canTransitionFiscalOperation,
  type FiscalOperationType,
  type FiscalOperationStatus,
  type FiscalOperationJournalEntry,
  type OfflineLease,
} from "./fiscalDomain";

/**
 * AP-4 Wave C — the real fiscal operation journal + offline authorization
 * lease engine. See `fiscalAdapter.ts`'s own doc comment for the honest,
 * provider-neutral framing this whole file operates under: no real PAX
 * A910SF/GMP-3 integration exists, so every fiscal operation here resolves
 * `"unavailable"` in production, and only the emulator's deterministic
 * test double can produce any other outcome.
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
const FISCAL_OPERATION_TYPE_VALUES = ["sale", "refund", "cancellation", "reconciliation", "dayEnd", "deviceResponse", "operatorAction"] as const;
function sanitizeFiscalOperationType(raw: unknown): FiscalOperationType {
  if (typeof raw !== "string" || !(FISCAL_OPERATION_TYPE_VALUES as readonly string[]).includes(raw)) {
    invalid(`operationType must be one of: ${FISCAL_OPERATION_TYPE_VALUES.join(", ")}.`);
  }
  return raw as FiscalOperationType;
}

interface StaffDeviceContext {
  organizationId: string;
  branchId: string;
  uid: string;
}
async function authorizeFiscalCommand(request: CallableRequest, data: Record<string, unknown>): Promise<StaffDeviceContext> {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
  const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");
  requireStaffPermission(request, organizationId, "manageFiscalDevices");
  requireBranchAccess(request, organizationId, branchId);
  await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);
  return { organizationId, branchId, uid: request.auth.uid };
}

// -----------------------------------------------------------------------
// recordFiscalOperation — the one callable every fiscal send goes through
// -----------------------------------------------------------------------

export const recordFiscalOperation = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const { organizationId, branchId, uid } = await authorizeFiscalCommand(request, data);
  const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
  const operationType = sanitizeFiscalOperationType(data.operationType);
  const amountMinorUnits = requirePositiveInt(data.amountMinorUnits, "amountMinorUnits");
  const currencyCode = requireNonEmptyString(data.currencyCode, "currencyCode");
  const idempotencyKey = requireNonEmptyString(data.idempotencyKey, "idempotencyKey");
  const checkId = typeof data.checkId === "string" && data.checkId.length > 0 ? data.checkId : null;
  const paymentAttemptId = typeof data.paymentAttemptId === "string" && data.paymentAttemptId.length > 0 ? data.paymentAttemptId : null;
  const refundRequestId = typeof data.refundRequestId === "string" && data.refundRequestId.length > 0 ? data.refundRequestId : null;
  const cashSessionId = typeof data.cashSessionId === "string" && data.cashSessionId.length > 0 ? data.cashSessionId : null;

  const db = getFirestore();
  const entryId = db.collection(FISCAL_OPERATION_JOURNAL_COLLECTION).doc().id;

  // Phase 1 (transactional): idempotent replay check + reserve as "sentToDevice".
  const phase1 = await db.runTransaction(async (tx) => {
    const existingSnap = await tx.get(
      db.collection(FISCAL_OPERATION_JOURNAL_COLLECTION)
        .where("organizationId", "==", organizationId)
        .where("branchId", "==", branchId)
        .where("idempotencyKey", "==", idempotencyKey),
    );
    if (!existingSnap.empty) {
      const existing = existingSnap.docs[0].data() as FiscalOperationJournalEntry;
      return { replay: true as const, entryId: existingSnap.docs[0].id, status: existing.status };
    }

    let cashSessionBusinessDate: string | null = null;
    if (cashSessionId) {
      const sessionSnap = await tx.get(db.collection(CASH_SESSIONS_COLLECTION).doc(cashSessionId));
      if (sessionSnap.exists) cashSessionBusinessDate = (sessionSnap.data() as { businessDate: string }).businessDate;
    }
    const configSnap = await tx.get(db.collection(BRANCH_PAYMENT_CONFIG_COLLECTION).doc(branchId));
    const config = configSnap.exists ? (configSnap.data() as BranchPaymentConfigDoc) : null;
    const now = Timestamp.now();
    const businessDate = cashSessionBusinessDate ?? computeBusinessDate(now.toMillis(), config?.timezone ?? "Europe/Istanbul", config?.businessDayCutoverHour ?? 0);

    const entry: FiscalOperationJournalEntry = {
      organizationId, branchId, deviceId, cashSessionId, checkId, paymentAttemptId, refundRequestId,
      businessDate, operationType, status: "sentToDevice", amountMinorUnits, currencyCode, idempotencyKey,
      providerId: resolveFiscalAdapter().providerId, providerReference: null, fiscalDocumentReference: null,
      responseSummary: null, actorStaffUid: uid, correlationId: generateCorrelationId(), createdAt: now, resolvedAt: null,
    };
    tx.set(db.collection(FISCAL_OPERATION_JOURNAL_COLLECTION).doc(entryId), entry);
    writeAuditEvent({
      tx, db, eventId: `${entryId}-sent`, organizationId, branchId,
      type: "fiscalOperation.sentToDevice", targetRef: db.collection(FISCAL_OPERATION_JOURNAL_COLLECTION).doc(entryId).path,
      newValue: { operationType, amountMinorUnits },
      actorType: "staff", actorUid: uid,
      correlationId: entry.correlationId, clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });
    return { replay: false as const, entryId, status: "sentToDevice" as FiscalOperationStatus };
  });

  if (phase1.replay) return { entryId: phase1.entryId, status: phase1.status };

  // Phase 2 (outside any transaction): the real device round-trip.
  const deviceResult = await resolveFiscalAdapter().send({ operationType: operationType as "sale" | "refund" | "cancellation" | "dayEnd", amountMinorUnits, currencyCode, idempotencyKey });

  // Phase 3 (transactional): resolve the journal entry from the device outcome.
  return db.runTransaction(async (tx) => {
    const entryRef = db.collection(FISCAL_OPERATION_JOURNAL_COLLECTION).doc(entryId);
    const entrySnap = await tx.get(entryRef);
    if (!entrySnap.exists) throw new HttpsError("internal", "Fiscal operation journal entry disappeared between reservation and resolution.");
    const entry = entrySnap.data() as FiscalOperationJournalEntry;
    if (entry.status !== "sentToDevice") {
      return { entryId, status: entry.status }; // already resolved by a racing call — idempotent
    }
    const now = Timestamp.now();
    let nextStatus: FiscalOperationStatus;
    let update: Partial<FiscalOperationJournalEntry>;
    if (deviceResult.outcome === "succeeded") {
      nextStatus = "succeeded";
      update = { status: nextStatus, fiscalDocumentReference: deviceResult.fiscalDocumentReference, providerReference: deviceResult.providerReference, responseSummary: deviceResult.responseSummary, resolvedAt: now };
    } else if (deviceResult.outcome === "declined") {
      nextStatus = "declined";
      update = { status: nextStatus, responseSummary: deviceResult.responseSummary, resolvedAt: now };
    } else if (deviceResult.outcome === "unavailable") {
      nextStatus = "unavailable";
      update = { status: nextStatus, responseSummary: deviceResult.responseSummary, resolvedAt: now };
    } else {
      nextStatus = "timedOut";
      update = { status: nextStatus, resolvedAt: now };
    }
    if (!canTransitionFiscalOperation(entry.status, nextStatus)) {
      throw new HttpsError("internal", `Invalid fiscal operation transition "${entry.status}" -> "${nextStatus}".`);
    }
    tx.update(entryRef, update);
    return { entryId, status: nextStatus };
  });
});

// -----------------------------------------------------------------------
// Offline authorization lease — server-issued, expiring, fail-closed
// -----------------------------------------------------------------------

const LEASE_MAX_VALIDITY_MINUTES = 12 * 60;
const LEASE_DEFAULT_VALIDITY_MINUTES = 4 * 60;
const LEASE_HARD_MAX_TRANSACTION_COUNT = 50;
const LEASE_HARD_MAX_TRANSACTION_VALUE_MINOR_UNITS = 500_000; // 5000.00 TRY — a server ceiling, not a client-trusted value

export const issueOfflineLease = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  const deviceId = requireNonEmptyString(data.deviceId, "deviceId");
  const deviceSessionId = requireNonEmptyString(data.deviceSessionId, "deviceSessionId");
  // Issuance itself requires processPayments — the same base capability the
  // lease will later authorize offline, never a broader one.
  requireStaffPermission(request, organizationId, "processPayments");
  requireBranchAccess(request, organizationId, branchId);
  await requireActiveDeviceSession(organizationId, branchId, deviceId, deviceSessionId);

  const requestedValidityMinutes = typeof data.validityMinutes === "number" && Number.isInteger(data.validityMinutes) && data.validityMinutes > 0
    ? Math.min(data.validityMinutes, LEASE_MAX_VALIDITY_MINUTES) : LEASE_DEFAULT_VALIDITY_MINUTES;
  const requestedMaxTransactionCount = typeof data.maxTransactionCount === "number" && Number.isInteger(data.maxTransactionCount) && data.maxTransactionCount > 0
    ? Math.min(data.maxTransactionCount, LEASE_HARD_MAX_TRANSACTION_COUNT) : LEASE_HARD_MAX_TRANSACTION_COUNT;
  const requestedMaxTransactionValue = typeof data.maxTransactionValueMinorUnits === "number" && Number.isInteger(data.maxTransactionValueMinorUnits) && data.maxTransactionValueMinorUnits > 0
    ? Math.min(data.maxTransactionValueMinorUnits, LEASE_HARD_MAX_TRANSACTION_VALUE_MINOR_UNITS) : LEASE_HARD_MAX_TRANSACTION_VALUE_MINOR_UNITS;

  const db = getFirestore();
  const now = Timestamp.now();
  const leaseRef = db.collection(OFFLINE_LEASES_COLLECTION).doc();
  const lease: OfflineLease = {
    leaseId: leaseRef.id, organizationId, branchId, deviceId, issuedToStaffUid: request.auth.uid,
    issuedAt: now, expiresAt: Timestamp.fromMillis(now.toMillis() + requestedValidityMinutes * 60_000),
    allowedPermissions: ["processPayments"], allowedTenderTypes: ["cash"],
    catalogVersion: now.toDate().toISOString(),
    maxTransactionCount: requestedMaxTransactionCount, maxTransactionValueMinorUnits: requestedMaxTransactionValue,
    lastSeenDeviceSequence: 0, transactionsUsed: 0, revoked: false, revokedAt: null, revokedReason: null,
    createdAt: now, version: 1,
  };
  await leaseRef.set(lease);
  await db.runTransaction(async (tx) => {
    writeAuditEvent({
      tx, db, eventId: `${leaseRef.id}-issued`, organizationId, branchId,
      type: "offlineLease.issued", targetRef: leaseRef.path,
      newValue: { deviceId, expiresAt: lease.expiresAt.toDate().toISOString(), maxTransactionCount: requestedMaxTransactionCount },
      actorType: "staff", actorUid: request.auth!.uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });
  });

  return {
    leaseId: lease.leaseId, expiresAt: lease.expiresAt.toDate().toISOString(),
    allowedTenderTypes: lease.allowedTenderTypes, maxTransactionCount: lease.maxTransactionCount,
    maxTransactionValueMinorUnits: lease.maxTransactionValueMinorUnits, catalogVersion: lease.catalogVersion,
  };
});

export const revokeOfflineLease = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const organizationId = requireNonEmptyString(data.organizationId, "organizationId");
  const branchId = requireNonEmptyString(data.branchId, "branchId");
  const leaseId = requireNonEmptyString(data.leaseId, "leaseId");
  const reason = requireNonEmptyString(data.reason, "reason");
  // Revocation (e.g. lost/stolen device) is manager-tier — a higher bar
  // than issuance, matching the asymmetric risk of a mis-issued lease vs.
  // a wrongly-un-revoked one.
  requireStaffPermission(request, organizationId, "approveCashReconciliation");
  requireBranchAccess(request, organizationId, branchId);

  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const leaseRef = db.collection(OFFLINE_LEASES_COLLECTION).doc(leaseId);
    const snap = await tx.get(leaseRef);
    if (!snap.exists) throw new HttpsError("not-found", "Offline lease not found.");
    const lease = snap.data() as OfflineLease;
    if (lease.organizationId !== organizationId || lease.branchId !== branchId) {
      throw new HttpsError("not-found", "Offline lease not found.");
    }
    if (lease.revoked) return { leaseId, revoked: true, idempotent: true };
    const now = Timestamp.now();
    tx.update(leaseRef, { revoked: true, revokedAt: now, revokedReason: reason, version: lease.version + 1 });
    writeAuditEvent({
      tx, db, eventId: `${leaseId}-revoked`, organizationId, branchId,
      type: "offlineLease.revoked", targetRef: leaseRef.path,
      newValue: { reason }, actorType: "staff", actorUid: request.auth!.uid,
      correlationId: generateCorrelationId(), clientRequestId: sanitizeClientRequestId(data.clientRequestId), now,
    });
    return { leaseId, revoked: true, idempotent: false };
  });
});
