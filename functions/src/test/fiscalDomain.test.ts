import { test } from "node:test";
import assert from "node:assert";
import { Timestamp } from "firebase-admin/firestore";
import { canTransitionFiscalOperation, validateOfflineLeaseForOperation, type OfflineLease } from "../fiscalDomain";

/** AP-4 Wave C — pure unit tests, no emulator required. */

test("canTransitionFiscalOperation: timedOut always routes through unknownReconciliationRequired, never a direct terminal", () => {
  assert.strictEqual(canTransitionFiscalOperation("timedOut", "unknownReconciliationRequired"), true);
  assert.strictEqual(canTransitionFiscalOperation("timedOut", "succeeded"), false);
  assert.strictEqual(canTransitionFiscalOperation("timedOut", "resolvedSucceeded"), false);
});

test("canTransitionFiscalOperation: succeeded/declined/unavailable are all terminal — nothing transitions out of them", () => {
  assert.strictEqual(canTransitionFiscalOperation("succeeded", "declined"), false);
  assert.strictEqual(canTransitionFiscalOperation("declined", "succeeded"), false);
  assert.strictEqual(canTransitionFiscalOperation("unavailable", "succeeded"), false);
});

function baseLease(overrides: Partial<OfflineLease> = {}): OfflineLease {
  const now = Timestamp.now();
  return {
    leaseId: "lease-1", organizationId: "org-1", branchId: "branch-1", deviceId: "device-1",
    issuedToStaffUid: "staff-1", issuedAt: now, expiresAt: Timestamp.fromMillis(now.toMillis() + 3_600_000),
    allowedPermissions: ["processPayments"], allowedTenderTypes: ["cash"], catalogVersion: "v1",
    maxTransactionCount: 10, maxTransactionValueMinorUnits: 100_000,
    lastSeenDeviceSequence: 0, transactionsUsed: 0, revoked: false, revokedAt: null, revokedReason: null,
    createdAt: now, version: 1,
    ...overrides,
  };
}

test("validateOfflineLeaseForOperation: a fresh lease's first operation (sequence 1) is ok", () => {
  const result = validateOfflineLeaseForOperation({ lease: baseLease(), nowMs: Date.now(), presentedDeviceSequence: 1, tenderType: "cash", amountMinorUnits: 5000 });
  assert.deepStrictEqual(result, { status: "ok" });
});

test("validateOfflineLeaseForOperation: revoked lease is rejected regardless of anything else", () => {
  const result = validateOfflineLeaseForOperation({ lease: baseLease({ revoked: true }), nowMs: Date.now(), presentedDeviceSequence: 1, tenderType: "cash", amountMinorUnits: 100 });
  assert.strictEqual(result.status, "revoked");
});

test("validateOfflineLeaseForOperation: an expired lease is rejected", () => {
  const now = Timestamp.now();
  const lease = baseLease({ expiresAt: Timestamp.fromMillis(now.toMillis() - 1000) });
  const result = validateOfflineLeaseForOperation({ lease, nowMs: now.toMillis(), presentedDeviceSequence: 1, tenderType: "cash", amountMinorUnits: 100 });
  assert.strictEqual(result.status, "expired");
});

test("validateOfflineLeaseForOperation: a non-cash tender is rejected — offline never authorizes card/mealCard/boncuk", () => {
  const result = validateOfflineLeaseForOperation({ lease: baseLease(), nowMs: Date.now(), presentedDeviceSequence: 1, tenderType: "card", amountMinorUnits: 100 });
  assert.strictEqual(result.status, "tender-not-allowed");
});

test("validateOfflineLeaseForOperation: replay protection — a device sequence that isn't lastSeen+1 is rejected, both a repeat and a gap", () => {
  const lease = baseLease({ lastSeenDeviceSequence: 3 });
  const repeat = validateOfflineLeaseForOperation({ lease, nowMs: Date.now(), presentedDeviceSequence: 3, tenderType: "cash", amountMinorUnits: 100 });
  assert.deepStrictEqual(repeat, { status: "replay", expectedSequence: 4 });
  const gap = validateOfflineLeaseForOperation({ lease, nowMs: Date.now(), presentedDeviceSequence: 6, tenderType: "cash", amountMinorUnits: 100 });
  assert.deepStrictEqual(gap, { status: "replay", expectedSequence: 4 });
  const correct = validateOfflineLeaseForOperation({ lease, nowMs: Date.now(), presentedDeviceSequence: 4, tenderType: "cash", amountMinorUnits: 100 });
  assert.deepStrictEqual(correct, { status: "ok" });
});

test("validateOfflineLeaseForOperation: transaction count cap — the Nth+1 operation beyond maxTransactionCount is rejected", () => {
  const lease = baseLease({ maxTransactionCount: 2, transactionsUsed: 2, lastSeenDeviceSequence: 2 });
  const result = validateOfflineLeaseForOperation({ lease, nowMs: Date.now(), presentedDeviceSequence: 3, tenderType: "cash", amountMinorUnits: 100 });
  assert.strictEqual(result.status, "transaction-count-exceeded");
});

test("validateOfflineLeaseForOperation: transaction value cap — a single operation exceeding maxTransactionValueMinorUnits is rejected", () => {
  const lease = baseLease({ maxTransactionValueMinorUnits: 1000 });
  const result = validateOfflineLeaseForOperation({ lease, nowMs: Date.now(), presentedDeviceSequence: 1, tenderType: "cash", amountMinorUnits: 1001 });
  assert.strictEqual(result.status, "transaction-value-exceeded");
  const atCap = validateOfflineLeaseForOperation({ lease, nowMs: Date.now(), presentedDeviceSequence: 1, tenderType: "cash", amountMinorUnits: 1000 });
  assert.strictEqual(atCap.status, "ok");
});
