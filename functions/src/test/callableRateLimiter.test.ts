import { test } from "node:test";
import assert from "node:assert";
import { shouldEnforceCallableRateLimit } from "../callableRateLimiter";

/**
 * Pure, environment-variable-branching unit tests for
 * `callableRateLimiter.ts`'s `shouldEnforceCallableRateLimit` — no
 * Firestore/Functions emulator involved (run via plain `npm test`), same
 * split as `tableGuestSessionConfig.test.ts`. The Firestore-transaction
 * counting logic itself (`enforceCallableRateLimit`) needs a real
 * Firestore and is covered separately by
 * `callableRateLimitEnforcement.test.ts` under `npm run test:emulator`.
 */

function withEnv(
  vars: Record<string, string | undefined>,
  fn: () => void,
): void {
  const previous: Record<string, string | undefined> = {};
  for (const key of Object.keys(vars)) {
    previous[key] = process.env[key];
    const value = vars[key];
    if (value === undefined) delete process.env[key];
    else process.env[key] = value;
  }
  try {
    fn();
  } finally {
    for (const key of Object.keys(previous)) {
      const value = previous[key];
      if (value === undefined) delete process.env[key];
      else process.env[key] = value;
    }
  }
}

test("shouldEnforceCallableRateLimit: on outside the emulator with no override", () => {
  withEnv(
    { FIRESTORE_EMULATOR_HOST: undefined, FORCE_CALLABLE_RATE_LIMIT_ENFORCEMENT: undefined },
    () => {
      assert.strictEqual(shouldEnforceCallableRateLimit(), true);
    },
  );
});

test("shouldEnforceCallableRateLimit: off under the emulator by default", () => {
  withEnv(
    {
      FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
      FORCE_CALLABLE_RATE_LIMIT_ENFORCEMENT: undefined,
    },
    () => {
      assert.strictEqual(shouldEnforceCallableRateLimit(), false);
    },
  );
});

test("shouldEnforceCallableRateLimit: force-override turns it on even under the emulator", () => {
  withEnv(
    {
      FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
      FORCE_CALLABLE_RATE_LIMIT_ENFORCEMENT: "true",
    },
    () => {
      assert.strictEqual(shouldEnforceCallableRateLimit(), true);
    },
  );
});

test("shouldEnforceCallableRateLimit: force-override value must be the exact string 'true'", () => {
  withEnv(
    {
      FIRESTORE_EMULATOR_HOST: "127.0.0.1:8080",
      FORCE_CALLABLE_RATE_LIMIT_ENFORCEMENT: "1",
    },
    () => {
      assert.strictEqual(shouldEnforceCallableRateLimit(), false);
    },
  );
});
