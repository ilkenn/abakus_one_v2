import { test } from "node:test";
import assert from "node:assert";
import { resolveFiscalAdapter } from "../fiscalAdapter";

/**
 * AP-4 Wave C — pure unit tests, no emulator required. Mirrors
 * `paymentProviderAdapter.test.ts` exactly: proves the one safety property
 * this file exists for — the deterministic test-only adapter is
 * structurally impossible to select outside the Functions emulator.
 */

test("resolveFiscalAdapter: outside the Functions emulator, the honest unconfigured adapter is selected — every operation resolves 'unavailable', never fabricated success", async () => {
  const adapter = resolveFiscalAdapter(false);
  assert.strictEqual(adapter.providerId, "unconfigured");
  const result = await adapter.send({ operationType: "sale", amountMinorUnits: 1000, currencyCode: "TRY", idempotencyKey: "any-key" });
  assert.strictEqual(result.outcome, "unavailable");
});

test("resolveFiscalAdapter: inside the Functions emulator, the deterministic test-only adapter is selected", async () => {
  const adapter = resolveFiscalAdapter(true);
  assert.strictEqual(adapter.providerId, "testOnlyDeterministic");
});

test("resolveFiscalAdapter: the real production gate reads the actual FUNCTIONS_EMULATOR env var, not a flag this code invents", () => {
  const original = process.env.FUNCTIONS_EMULATOR;
  try {
    delete process.env.FUNCTIONS_EMULATOR;
    assert.strictEqual(resolveFiscalAdapter().providerId, "unconfigured");
    process.env.FUNCTIONS_EMULATOR = "true";
    assert.strictEqual(resolveFiscalAdapter().providerId, "testOnlyDeterministic");
  } finally {
    if (original === undefined) delete process.env.FUNCTIONS_EMULATOR;
    else process.env.FUNCTIONS_EMULATOR = original;
  }
});

test("TestOnlyDeterministicFiscalAdapter: FORCE_DECLINE/FORCE_TIMEOUT/FORCE_UNAVAILABLE markers deterministically exercise every FiscalDeviceOutcome branch", async () => {
  const adapter = resolveFiscalAdapter(true);
  const declined = await adapter.send({ operationType: "sale", amountMinorUnits: 1000, currencyCode: "TRY", idempotencyKey: "x-FORCE_DECLINE-1" });
  assert.strictEqual(declined.outcome, "declined");
  const timedOut = await adapter.send({ operationType: "sale", amountMinorUnits: 1000, currencyCode: "TRY", idempotencyKey: "x-FORCE_TIMEOUT-1" });
  assert.strictEqual(timedOut.outcome, "timedOut");
  const unavailable = await adapter.send({ operationType: "sale", amountMinorUnits: 1000, currencyCode: "TRY", idempotencyKey: "x-FORCE_UNAVAILABLE-1" });
  assert.strictEqual(unavailable.outcome, "unavailable");
  const succeeded = await adapter.send({ operationType: "sale", amountMinorUnits: 1000, currencyCode: "TRY", idempotencyKey: "x-plain-1" });
  assert.strictEqual(succeeded.outcome, "succeeded");
  if (succeeded.outcome === "succeeded") {
    assert.ok(succeeded.fiscalDocumentReference.length > 0);
    assert.ok(succeeded.providerReference.length > 0);
  }
});
