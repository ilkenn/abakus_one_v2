import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { enforceCallableRateLimit } from "../callableRateLimiter";

/**
 * Emulator-backed proof that `enforceCallableRateLimit`'s Firestore-counter
 * mechanism itself actually throttles — ADR-049.
 *
 * **Deliberately does not call `resolveTableQrToken`/`openTableGuestSession`
 * over HTTP** the way `tableGuestSession.test.ts` does. Those callables run
 * inside the separate Functions Emulator process; this test process cannot
 * reach into that process's `process.env` to flip
 * `FORCE_CALLABLE_RATE_LIMIT_ENFORCEMENT` on for it without also affecting
 * every other emulator test file sharing that one running emulator for the
 * whole `npm run test:emulator` session — exactly the cross-contamination
 * risk `shouldEnforceCallableRateLimit`'s emulator-off-by-default exists to
 * avoid. Calling `enforceCallableRateLimit` directly, in this test's own
 * process, sidesteps that entirely: the env var only has to be true here,
 * and the real `resolveTableQrToken`/`openTableGuestSession` test suites
 * remain completely unaffected (they never set this variable, so they keep
 * seeing enforcement OFF under the emulator, exactly as before this file
 * existed).
 *
 * Uses distinct `functionName` values per test (never the real
 * `"resolveTableQrToken"`/`"openTableGuestSession"`) so this file's own
 * bucket documents can never collide with anything a real callable test
 * might someday also force-enable.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";

let app: admin.app.App;

before(() => {
  process.env.FORCE_CALLABLE_RATE_LIMIT_ENFORCEMENT = "true";
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});

after(async () => {
  delete process.env.FORCE_CALLABLE_RATE_LIMIT_ENFORCEMENT;
  await app.delete();
});

const RULE = { windowMs: 60_000, maxAttempts: 3 };
const BASE_NOW = new Date("2026-10-20T10:00:00.000Z");

async function assertResourceExhausted(promise: Promise<void>): Promise<void> {
  await assert.rejects(promise, (error: unknown) => {
    assert.strictEqual((error as { code?: string }).code, "resource-exhausted");
    return true;
  });
}

test("enforceCallableRateLimit: allows calls up to maxAttempts, then throws resource-exhausted", async () => {
  const uid = "uid-basic-throttle";
  for (let i = 0; i < RULE.maxAttempts; i += 1) {
    await enforceCallableRateLimit({
      functionName: "testFn-basic",
      uid,
      ip: null,
      uidRule: RULE,
      ipRule: RULE,
      now: BASE_NOW,
    });
  }

  await assertResourceExhausted(
    enforceCallableRateLimit({
      functionName: "testFn-basic",
      uid,
      ip: null,
      uidRule: RULE,
      ipRule: RULE,
      now: BASE_NOW,
    }),
  );
});

test("enforceCallableRateLimit: the window resets after it expires, even for an already-exhausted bucket", async () => {
  const uid = "uid-window-reset";
  for (let i = 0; i < RULE.maxAttempts; i += 1) {
    await enforceCallableRateLimit({
      functionName: "testFn-window-reset",
      uid,
      ip: null,
      uidRule: RULE,
      ipRule: RULE,
      now: BASE_NOW,
    });
  }
  await assertResourceExhausted(
    enforceCallableRateLimit({
      functionName: "testFn-window-reset",
      uid,
      ip: null,
      uidRule: RULE,
      ipRule: RULE,
      now: BASE_NOW,
    }),
  );

  // A full window later, the same uid is allowed again — the bucket
  // started a fresh window rather than staying permanently exhausted.
  const afterWindow = new Date(BASE_NOW.getTime() + RULE.windowMs + 1);
  await enforceCallableRateLimit({
    functionName: "testFn-window-reset",
    uid,
    ip: null,
    uidRule: RULE,
    ipRule: RULE,
    now: afterWindow,
  });
});

test("enforceCallableRateLimit: uid and IP buckets are tracked independently — an exhausted uid still blocks even behind a fresh IP, and vice versa", async () => {
  const uid = "uid-independent-a";
  const ip = "203.0.113.5";

  // Exhaust the uid bucket only, always from the same (fresh so far) IP.
  for (let i = 0; i < RULE.maxAttempts; i += 1) {
    await enforceCallableRateLimit({
      functionName: "testFn-independent",
      uid,
      ip,
      uidRule: RULE,
      ipRule: { windowMs: 60_000, maxAttempts: 1000 },
      now: BASE_NOW,
    });
  }

  // A different uid behind the SAME ip is unaffected by the first uid's
  // exhaustion — proves the uid dimension doesn't leak into the ip one.
  await enforceCallableRateLimit({
    functionName: "testFn-independent",
    uid: "uid-independent-b",
    ip,
    uidRule: RULE,
    ipRule: { windowMs: 60_000, maxAttempts: 1000 },
    now: BASE_NOW,
  });

  // The original uid, now behind a brand-new IP, is still blocked — the
  // uid bucket alone is sufficient to reject, independent of IP.
  await assertResourceExhausted(
    enforceCallableRateLimit({
      functionName: "testFn-independent",
      uid,
      ip: "198.51.100.9",
      uidRule: RULE,
      ipRule: { windowMs: 60_000, maxAttempts: 1000 },
      now: BASE_NOW,
    }),
  );
});

test("enforceCallableRateLimit: a null uid (unauthenticated caller) is limited by IP alone", async () => {
  const ip = "192.0.2.10";
  for (let i = 0; i < RULE.maxAttempts; i += 1) {
    await enforceCallableRateLimit({
      functionName: "testFn-ip-only",
      uid: null,
      ip,
      uidRule: RULE,
      ipRule: RULE,
      now: BASE_NOW,
    });
  }

  await assertResourceExhausted(
    enforceCallableRateLimit({
      functionName: "testFn-ip-only",
      uid: null,
      ip,
      uidRule: RULE,
      ipRule: RULE,
      now: BASE_NOW,
    }),
  );
});

test("enforceCallableRateLimit: a null uid and a null ip never throws (nothing to key a bucket on)", async () => {
  await enforceCallableRateLimit({
    functionName: "testFn-no-dimensions",
    uid: null,
    ip: null,
    uidRule: RULE,
    ipRule: RULE,
    now: BASE_NOW,
  });
});
