import { test } from "node:test";
import assert from "node:assert";
import { resolveProviderAdapter } from "../paymentProviderAdapter";

/**
 * AP-4 Wave A — pure unit tests, no emulator required. Proves the one
 * safety property this file exists for: the deterministic test-only
 * adapter is structurally impossible to select outside the Functions
 * emulator, and the honest "nothing is configured" adapter is what a real
 * deployment actually gets.
 */

test("resolveProviderAdapter: outside the Functions emulator, the honest unconfigured adapter is selected — never the test-only deterministic one", async () => {
  const adapter = resolveProviderAdapter(false);
  assert.strictEqual(adapter.providerId, "unconfigured");
  const result = await adapter.charge({ amountMinorUnits: 1000, currencyCode: "TRY", idempotencyKey: "any-key" });
  assert.strictEqual(result.outcome, "declined");
});

test("resolveProviderAdapter: inside the Functions emulator, the deterministic test-only adapter is selected", async () => {
  const adapter = resolveProviderAdapter(true);
  assert.strictEqual(adapter.providerId, "testOnlyDeterministic");
});

test("resolveProviderAdapter: the real production gate reads the actual FUNCTIONS_EMULATOR env var, not a flag this code invents", () => {
  const original = process.env.FUNCTIONS_EMULATOR;
  try {
    delete process.env.FUNCTIONS_EMULATOR;
    assert.strictEqual(resolveProviderAdapter().providerId, "unconfigured");
    process.env.FUNCTIONS_EMULATOR = "true";
    assert.strictEqual(resolveProviderAdapter().providerId, "testOnlyDeterministic");
  } finally {
    if (original === undefined) delete process.env.FUNCTIONS_EMULATOR;
    else process.env.FUNCTIONS_EMULATOR = original;
  }
});

test("TestOnlyDeterministicAdapter: FORCE_DECLINE/FORCE_TIMEOUT markers deterministically exercise every ProviderOutcome branch", async () => {
  const adapter = resolveProviderAdapter(true);
  const declined = await adapter.charge({ amountMinorUnits: 1000, currencyCode: "TRY", idempotencyKey: "x-FORCE_DECLINE-1" });
  assert.strictEqual(declined.outcome, "declined");
  const timedOut = await adapter.charge({ amountMinorUnits: 1000, currencyCode: "TRY", idempotencyKey: "x-FORCE_TIMEOUT-1" });
  assert.strictEqual(timedOut.outcome, "timedOut");
  const succeeded = await adapter.charge({ amountMinorUnits: 1000, currencyCode: "TRY", idempotencyKey: "x-plain-1" });
  assert.strictEqual(succeeded.outcome, "succeeded");
});
