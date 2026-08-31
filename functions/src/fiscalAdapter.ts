/**
 * AP-4 Wave C — the fiscal-device boundary. Mirrors `paymentProviderAdapter
 * .ts`'s own honest structure exactly, for the identical reason: a
 * confirmed, exhaustive repo search before writing this file found ZERO
 * PAX A910SF SDK, ZERO GMP-3/YN ÖKC protocol specification, and ZERO vendor
 * credential material anywhere in this repository — see
 * `docs/ap4_wave_c_vendor_dependencies.md` for the full dossier and
 * `docs/payment_cash_fiscal_architecture.md` §4/§14/§21/§22, which already
 * documented this as a standing, confirmed gap before this wave started.
 *
 * This file NEVER invents a PAX command, a GMP-3 byte sequence, a fiscal-
 * document field, or a certification claim. `UnconfiguredFiscalAdapter` is
 * what a real deployment actually gets today — every fiscal operation
 * resolves `"unavailable"`, honestly, never silently pretending success.
 * `TestOnlyDeterministicFiscalAdapter` exists only so the real journal/
 * state-machine/idempotency engine (`fiscalEngine.ts`) can be exercised in
 * tests — structurally impossible to select outside the Functions emulator
 * (same `FUNCTIONS_EMULATOR` gate as `paymentProviderAdapter.ts`).
 *
 * **A simulator passing this adapter's tests is never real PAX/GMP-3
 * certification** — see the governing instruction's own explicit rule.
 * `PAX_A910SF_PRODUCTION_ADAPTER_COMPLETE=NO` and
 * `GMP3_REAL_DEVICE_ACCEPTANCE_COMPLETE=NO` in the AP-4 final report are the
 * honest, structural consequence of this file's own contents, not an
 * oversight.
 */

export type FiscalDeviceOutcome =
  | { outcome: "succeeded"; fiscalDocumentReference: string; providerReference: string; responseSummary: string }
  | { outcome: "declined"; responseSummary: string }
  | { outcome: "timedOut" }
  | { outcome: "unavailable"; responseSummary: string };

export interface FiscalDevicePort {
  readonly providerId: string;
  send(params: {
    operationType: "sale" | "refund" | "cancellation" | "dayEnd";
    amountMinorUnits: number;
    currencyCode: string;
    idempotencyKey: string;
  }): Promise<FiscalDeviceOutcome>;
}

/**
 * The honest "no real fiscal device is configured" adapter — what
 * production actually gets today. Never fabricates a fiscal document
 * reference; every operation resolves `"unavailable"` with a clear,
 * non-fabricated reason. Per the locked offline rule this same repo's own
 * governing instruction states — "cash and only a fiscal/payment-device-
 * verified sale may continue" when offline — an `unavailable` fiscal
 * result is exactly the signal that keeps a NON-cash sale correctly
 * blocked; it is not an error to silently route around.
 */
class UnconfiguredFiscalAdapter implements FiscalDevicePort {
  readonly providerId = "unconfigured";
  async send(): Promise<FiscalDeviceOutcome> {
    return { outcome: "unavailable", responseSummary: "No real fiscal device is configured for this environment." };
  }
}

/**
 * Deterministic, emulator/test-only. Mirrors `paymentProviderAdapter.ts`'s
 * `TestOnlyDeterministicAdapter` exactly — a fiscal send succeeds unless
 * the caller's `idempotencyKey` contains `"FORCE_DECLINE"`,
 * `"FORCE_TIMEOUT"`, or `"FORCE_UNAVAILABLE"`. NEVER reachable outside
 * `FUNCTIONS_EMULATOR=true`.
 */
class TestOnlyDeterministicFiscalAdapter implements FiscalDevicePort {
  readonly providerId = "testOnlyDeterministic";
  async send(params: { operationType: string; amountMinorUnits: number; currencyCode: string; idempotencyKey: string }): Promise<FiscalDeviceOutcome> {
    if (params.idempotencyKey.includes("FORCE_DECLINE")) {
      return { outcome: "declined", responseSummary: "Test-forced fiscal decline." };
    }
    if (params.idempotencyKey.includes("FORCE_TIMEOUT")) {
      return { outcome: "timedOut" };
    }
    if (params.idempotencyKey.includes("FORCE_UNAVAILABLE")) {
      return { outcome: "unavailable", responseSummary: "Test-forced device unavailable." };
    }
    return {
      outcome: "succeeded",
      fiscalDocumentReference: `test-fiscal-doc-${params.idempotencyKey}`,
      providerReference: `test-fiscal-${params.idempotencyKey}`,
      responseSummary: `Test-only deterministic fiscal approval for ${params.amountMinorUnits} ${params.currencyCode}.`,
    };
  }
}

/** Same structural gate as `resolveProviderAdapter` — reads the REAL Firebase-emulator-set `FUNCTIONS_EMULATOR` env var, nothing a client or deploy config can influence. */
export function resolveFiscalAdapter(
  isFunctionsEmulator: boolean = process.env.FUNCTIONS_EMULATOR === "true",
): FiscalDevicePort {
  return isFunctionsEmulator ? new TestOnlyDeterministicFiscalAdapter() : new UnconfiguredFiscalAdapter();
}
