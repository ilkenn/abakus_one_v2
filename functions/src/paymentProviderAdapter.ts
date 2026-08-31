/**
 * AP-4 Wave A — the payment-provider boundary. Mirrors `docs
 * /payment_cash_fiscal_architecture.md`'s explicit non-goal: "no specific
 * provider chosen." This file NEVER fabricates a real Stripe/Adyen/iyzico/
 * card-network integration — `lib/features/payment/data/adapters/*.dart`'s
 * own honest `NoOp` stance (BR-PAY-003: every provider adapter returns
 * `notConfigured`) is mirrored here on the server side.
 *
 * What this file DOES provide, honestly: the real conservation/state-
 * machine/idempotency engine (`paymentAttempts.ts`) needs SOME way to
 * exercise a `card`/`mealCard` tender's full state-machine path (including
 * a genuine provider round-trip shape) in tests and local development,
 * without claiming any real vendor integration exists. `TestOnlyDeterministicAdapter`
 * is that — clearly named, clearly documented, and structurally impossible
 * to select outside the Functions emulator (see `resolveProviderAdapter`'s
 * gate below, which checks the real, standard `FUNCTIONS_EMULATOR` env var
 * the Firebase emulator itself sets — not a flag this code invents or a
 * client can influence).
 *
 * `cash` and `boncuk` never go through this port at all — cash settles
 * synchronously (the cashier physically holds the money; there is no
 * external provider round-trip), and `boncuk` wraps the existing, real,
 * closed `loyaltyLedger.ts` mechanism directly (see `paymentAttempts.ts`).
 * This port exists ONLY for `card`/`mealCard`.
 */

export type ProviderOutcome =
  | { outcome: "succeeded"; providerRef: string; responseSummary: string }
  | { outcome: "declined"; declineReason: string }
  | { outcome: "timedOut" };

export interface PaymentProviderPort {
  readonly providerId: string;
  charge(params: {
    amountMinorUnits: number;
    currencyCode: string;
    idempotencyKey: string;
  }): Promise<ProviderOutcome>;
}

/**
 * The honest "nothing is configured" adapter — mirrors
 * `lib/features/payment/data/adapters/stripe_adapter.dart` etc. exactly:
 * every real card/meal-card tender declines with a clear, non-fabricated
 * reason. This is what production actually does today, and is not a
 * placeholder to be silently swapped later without an explicit ADR — wiring
 * a real provider is its own architecture-change-sized decision (mirrors
 * `CLAUDE.md` §5's "wiring any real Firebase service is an architecture
 * change" reasoning, applied to payment providers).
 */
class UnconfiguredProviderAdapter implements PaymentProviderPort {
  readonly providerId = "unconfigured";
  async charge(): Promise<ProviderOutcome> {
    return { outcome: "declined", declineReason: "No real payment provider is configured for this environment." };
  }
}

/**
 * Deterministic, emulator/test-only. A charge succeeds unless the caller's
 * `idempotencyKey` contains the literal substring `"FORCE_DECLINE"` or
 * `"FORCE_TIMEOUT"` — this lets tests exercise every `ProviderOutcome`
 * branch deterministically, without any randomness or real network call.
 * NEVER reachable outside `FUNCTIONS_EMULATOR=true` — see the gate in
 * `resolveProviderAdapter` below.
 */
class TestOnlyDeterministicAdapter implements PaymentProviderPort {
  readonly providerId = "testOnlyDeterministic";
  async charge(params: { amountMinorUnits: number; currencyCode: string; idempotencyKey: string }): Promise<ProviderOutcome> {
    if (params.idempotencyKey.includes("FORCE_DECLINE")) {
      return { outcome: "declined", declineReason: "Test-forced decline." };
    }
    if (params.idempotencyKey.includes("FORCE_TIMEOUT")) {
      return { outcome: "timedOut" };
    }
    return {
      outcome: "succeeded",
      providerRef: `test-${params.idempotencyKey}`,
      responseSummary: `Test-only deterministic approval for ${params.amountMinorUnits} ${params.currencyCode}.`,
    };
  }
}

/**
 * The one place a `card`/`mealCard` `PaymentAttempt` resolves which adapter
 * to call. `isFunctionsEmulator` defaults to reading the REAL Firebase-
 * emulator-set `FUNCTIONS_EMULATOR` env var — not a flag any client
 * request, Firestore document, or deploy-time config this code owns can
 * influence — so `TestOnlyDeterministicAdapter` is structurally impossible
 * to select in a real deployed Functions environment. Proven directly by
 * `paymentProviderAdapter.test.ts`'s "production exclusion" test.
 */
export function resolveProviderAdapter(
  isFunctionsEmulator: boolean = process.env.FUNCTIONS_EMULATOR === "true",
): PaymentProviderPort {
  return isFunctionsEmulator ? new TestOnlyDeterministicAdapter() : new UnconfiguredProviderAdapter();
}
