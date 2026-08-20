import { test } from "node:test";
import assert from "node:assert";
import {
  LEDGER_ENTRY_TYPES,
  sanitizeEntryType,
  deriveLoyaltyLedgerEntryId,
  BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK,
  BONCUK_REDEMPTION_VALUE_MINOR_UNITS_PER_BONCUK,
} from "../loyaltyLedger";

/**
 * Pure, no-emulator unit tests for the Boncuk loyalty ledger's shared
 * domain contracts — P1 (2026-08-20). Mirrors `takeawayPricing.test.ts`'s
 * own "no Firestore/Functions/Auth emulator involved" shape: every
 * function under test here is a pure function of its arguments.
 */

test("sanitizeEntryType accepts every closed entry type", () => {
  for (const type of LEDGER_ENTRY_TYPES) {
    assert.strictEqual(sanitizeEntryType(type), type);
  }
});

test("sanitizeEntryType rejects an unrecognized string", () => {
  assert.throws(() => sanitizeEntryType("somethingElse"), /entryType must be one of/);
});

test("sanitizeEntryType rejects a non-string value", () => {
  assert.throws(() => sanitizeEntryType(42), /entryType must be one of/);
  assert.throws(() => sanitizeEntryType(null), /entryType must be one of/);
  assert.throws(() => sanitizeEntryType(undefined), /entryType must be one of/);
});

test("BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK is exactly 5000 (50 TL = 1 Boncuk)", () => {
  assert.strictEqual(BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK, 5000);
  assert.strictEqual(Number.isInteger(BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK), true);
});

test("BONCUK_REDEMPTION_VALUE_MINOR_UNITS_PER_BONCUK is exactly 200 (1 Boncuk = 2 TL)", () => {
  assert.strictEqual(BONCUK_REDEMPTION_VALUE_MINOR_UNITS_PER_BONCUK, 200);
  assert.strictEqual(Number.isInteger(BONCUK_REDEMPTION_VALUE_MINOR_UNITS_PER_BONCUK), true);
});

test("deriveLoyaltyLedgerEntryId is deterministic for identical trusted inputs", () => {
  const params = {
    organizationId: "org-1",
    customerId: "uid-1",
    entryType: "orderEarn" as const,
    sourceId: "order-1",
  };
  assert.strictEqual(deriveLoyaltyLedgerEntryId(params), deriveLoyaltyLedgerEntryId(params));
});

test("deriveLoyaltyLedgerEntryId differs when organizationId differs", () => {
  const base = { customerId: "uid-1", entryType: "orderEarn" as const, sourceId: "order-1" };
  const idA = deriveLoyaltyLedgerEntryId({ ...base, organizationId: "org-1" });
  const idB = deriveLoyaltyLedgerEntryId({ ...base, organizationId: "org-2" });
  assert.notStrictEqual(idA, idB);
});

test("deriveLoyaltyLedgerEntryId differs when entryType differs", () => {
  const base = { organizationId: "org-1", customerId: "uid-1", sourceId: "order-1" };
  const idA = deriveLoyaltyLedgerEntryId({ ...base, entryType: "orderEarn" });
  const idB = deriveLoyaltyLedgerEntryId({ ...base, entryType: "orderEarnReversal" });
  assert.notStrictEqual(idA, idB);
});

test("deriveLoyaltyLedgerEntryId differs when sourceId differs", () => {
  const base = { organizationId: "org-1", customerId: "uid-1", entryType: "orderEarn" as const };
  const idA = deriveLoyaltyLedgerEntryId({ ...base, sourceId: "order-1" });
  const idB = deriveLoyaltyLedgerEntryId({ ...base, sourceId: "order-2" });
  assert.notStrictEqual(idA, idB);
});

test("deriveLoyaltyLedgerEntryId differs when customerId differs (defense-in-depth, even though sourceId already scopes to one customer in practice)", () => {
  const base = { organizationId: "org-1", entryType: "orderEarn" as const, sourceId: "order-1" };
  const idA = deriveLoyaltyLedgerEntryId({ ...base, customerId: "uid-1" });
  const idB = deriveLoyaltyLedgerEntryId({ ...base, customerId: "uid-2" });
  assert.notStrictEqual(idA, idB);
});

test("deriveLoyaltyLedgerEntryId is a bounded, Firestore-safe document id", () => {
  const id = deriveLoyaltyLedgerEntryId({
    organizationId: "org-1",
    customerId: "uid-1",
    entryType: "orderEarn",
    sourceId: "order-1",
  });
  // "loyalty-" (8) + 64-char hex sha256 digest = 72 chars — far under
  // Firestore's 1500-byte document-id limit.
  assert.strictEqual(id.length, 72);
  assert.match(id, /^loyalty-[0-9a-f]{64}$/);
  assert.strictEqual(id.includes("/"), false);
  assert.strictEqual(id.includes("."), false);
  assert.strictEqual(id.trim(), id);
});

test("deriveLoyaltyLedgerEntryId never accepts phone/email as an input — no raw PII possible", () => {
  // The function's own type signature has no phone/email parameter at
  // all; this test documents that guarantee rather than exercising a
  // runtime check (there is nothing to sanitize away, since it was never
  // accepted in the first place).
  const id = deriveLoyaltyLedgerEntryId({
    organizationId: "org-1",
    customerId: "uid-1",
    entryType: "orderEarn",
    sourceId: "order-1",
  });
  assert.strictEqual(id.includes("@"), false);
  assert.strictEqual(id.includes("+9"), false);
});
