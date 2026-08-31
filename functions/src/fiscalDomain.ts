import type { Timestamp } from "firebase-admin/firestore";

/**
 * AP-4 Wave C — fiscal device boundary + offline authorization contracts.
 * No Firestore I/O lives here — mirrors `paymentDomain.ts`'s own shape.
 *
 * **Confirmed by exhaustive repo search before writing a single line here**:
 * zero PAX A910SF SDK, zero GMP-3/YN ÖKC protocol specification, zero
 * vendor credential material anywhere in this repository
 * (`docs/payment_cash_fiscal_architecture.md` §4/§14/§21/§22 already
 * documents this as a confirmed, standing gap). This file therefore
 * defines a provider-NEUTRAL boundary only — no PAX command, no GMP-3
 * byte sequence, no fiscal-document field invented. See
 * `docs/ap4_wave_c_vendor_dependencies.md` for the full, explicit
 * controlled-external-dependency dossier this produces.
 */

export const FISCAL_OPERATION_JOURNAL_COLLECTION = "fiscalOperationJournal";
export const OFFLINE_LEASES_COLLECTION = "offlineLeases";

// ---------------------------------------------------------------------
// Fiscal operation journal — append-only, correlates every actor/artifact
// ---------------------------------------------------------------------

export const FISCAL_OPERATION_TYPES = [
  "sale",
  "refund",
  "cancellation",
  "reconciliation",
  "dayEnd",
  "deviceResponse",
  "operatorAction",
] as const;
export type FiscalOperationType = (typeof FISCAL_OPERATION_TYPES)[number];

/**
 * Payment and fiscal outcomes are modeled INDEPENDENTLY (the governing
 * instruction's own locked requirement) — this status describes ONLY the
 * fiscal-document side of an operation, never conflated with
 * `PaymentAttemptStatus`. `timedOut` always routes to
 * `unknownReconciliationRequired` next — a definitive provider answer is
 * never second-guessed, but a timeout is never silently retried or
 * silently treated as failure either (mirrors `PaymentAttemptStatus`'s own
 * locked shape in `paymentDomain.ts`).
 */
export type FiscalOperationStatus =
  | "initiated"
  | "sentToDevice"
  | "succeeded"
  | "declined"
  | "timedOut"
  | "unavailable"
  | "unknownReconciliationRequired"
  | "resolvedSucceeded"
  | "resolvedFailed"
  | "manualInterventionRequired";

const FISCAL_OPERATION_TRANSITIONS: Readonly<Record<FiscalOperationStatus, readonly FiscalOperationStatus[]>> = {
  initiated: ["sentToDevice", "unavailable"],
  sentToDevice: ["succeeded", "declined", "timedOut"],
  succeeded: [],
  declined: [],
  unavailable: [],
  timedOut: ["unknownReconciliationRequired"],
  unknownReconciliationRequired: ["resolvedSucceeded", "resolvedFailed", "manualInterventionRequired"],
  resolvedSucceeded: [],
  resolvedFailed: [],
  manualInterventionRequired: ["resolvedSucceeded", "resolvedFailed"],
};

export function canTransitionFiscalOperation(from: FiscalOperationStatus, to: FiscalOperationStatus): boolean {
  return FISCAL_OPERATION_TRANSITIONS[from].includes(to);
}

export interface FiscalOperationJournalEntry {
  organizationId: string;
  branchId: string;
  deviceId: string;
  cashSessionId: string | null;
  checkId: string | null;
  paymentAttemptId: string | null;
  refundRequestId: string | null;
  businessDate: string; // YYYY-MM-DD, same `computeBusinessDate` source as cashDomain.ts
  operationType: FiscalOperationType;
  status: FiscalOperationStatus;
  amountMinorUnits: number;
  currencyCode: string;
  idempotencyKey: string;
  /** Vendor-neutral — the honest `UnconfiguredFiscalAdapter`'s own id ("unconfigured") until a real vendor adapter exists. */
  providerId: string;
  /** Opaque device/provider correlation reference — NEVER PAN/PIN/OTP/private-key material (C2's persistence ban, same as `PaymentAttemptDoc.providerRef`). */
  providerReference: string | null;
  fiscalDocumentReference: string | null;
  /** Sanitized text only — see `providerReference`'s own ban. */
  responseSummary: string | null;
  actorStaffUid: string;
  correlationId: string;
  createdAt: Timestamp;
  resolvedAt: Timestamp | null;
}

// ---------------------------------------------------------------------
// Offline authorization lease — server-issued, expiring, fail-closed
// ---------------------------------------------------------------------

/**
 * Locked rule this implements exactly: "When Firebase/internet is
 * unavailable, cash and only a fiscal/payment-device-verified sale may
 * continue." A lease therefore only ever authorizes `["cash"]` this wave —
 * `allowedTenderTypes` is included in the shape for forward-compatibility
 * with a future real fiscal-device-verified card path, but nothing in this
 * codebase issues a lease with any other value yet.
 */
export interface OfflineLease {
  leaseId: string;
  organizationId: string;
  branchId: string;
  deviceId: string;
  issuedToStaffUid: string;
  issuedAt: Timestamp;
  expiresAt: Timestamp;
  allowedPermissions: readonly string[]; // snapshot at issuance — never re-derived client-side
  allowedTenderTypes: readonly string[]; // always ["cash"] this wave — see doc comment above
  catalogVersion: string; // opaque staleness marker the client can compare against on reconnect
  maxTransactionCount: number;
  maxTransactionValueMinorUnits: number;
  /** Monotonically increasing per lease — replay protection. Starts at 0; the FIRST offline operation must present sequence 1. */
  lastSeenDeviceSequence: number;
  transactionsUsed: number;
  revoked: boolean;
  revokedAt: Timestamp | null;
  revokedReason: string | null;
  createdAt: Timestamp;
  version: number;
}

export type OfflineLeaseValidationResult =
  | { status: "ok" }
  | { status: "expired" }
  | { status: "revoked" }
  | { status: "replay"; expectedSequence: number }
  | { status: "tender-not-allowed" }
  | { status: "transaction-count-exceeded" }
  | { status: "transaction-value-exceeded" };

/**
 * Pure — every check a server-side consumer (e.g. `recordPaymentAttempt`'s
 * offline-replay path) must run before honoring a client-presented lease +
 * device sequence + tender type + amount. Fails closed on every branch —
 * there is no "unknown -> allow" path.
 */
export function validateOfflineLeaseForOperation(params: {
  lease: OfflineLease;
  nowMs: number;
  presentedDeviceSequence: number;
  tenderType: string;
  amountMinorUnits: number;
}): OfflineLeaseValidationResult {
  const { lease, nowMs, presentedDeviceSequence, tenderType, amountMinorUnits } = params;
  if (lease.revoked) return { status: "revoked" };
  if (lease.expiresAt.toMillis() < nowMs) return { status: "expired" };
  if (!lease.allowedTenderTypes.includes(tenderType)) return { status: "tender-not-allowed" };
  if (presentedDeviceSequence !== lease.lastSeenDeviceSequence + 1) {
    return { status: "replay", expectedSequence: lease.lastSeenDeviceSequence + 1 };
  }
  if (lease.transactionsUsed + 1 > lease.maxTransactionCount) return { status: "transaction-count-exceeded" };
  if (amountMinorUnits > lease.maxTransactionValueMinorUnits) return { status: "transaction-value-exceeded" };
  return { status: "ok" };
}
