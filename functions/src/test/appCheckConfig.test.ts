import { test } from "node:test";
import assert from "node:assert";
import path from "node:path";
import { shouldEnforceAppCheck } from "../appCheckConfig";

/**
 * Direct unit tests for `shouldEnforceAppCheck()` — Faz D.3.2 (Table QR
 * App Check Hardening), extended Faz D.3.2.1 (Account Deletion
 * Authorization + App Check Fail-Safe Audit). Also proves, by real
 * module-wiring inspection rather than by simulating a real App Check
 * token (this repo deliberately never fakes one), that every
 * App-Check-ready Function — the Table QR pair
 * (`resolveTableQrToken`/`openTableGuestSession`), the Takeaway trio
 * (`resolveTakeawayQrToken`/`openTakeawayGuestSession`/
 * `submitTakeawayOrder`), and `processAccountDeletion` (Faz D.3.2.1) —
 * all wire the exact SAME shared `appCheckConfig.ts` function into their
 * `onCall` options — not independent copies, and not a hardcoded boolean.
 *
 * No end-to-end "does the deployed Function actually reject a request
 * missing a valid App Check token" test is attempted here:
 * `shouldEnforceAppCheck()` is unconditionally `false` whenever
 * `FIRESTORE_EMULATOR_HOST` is set (a deliberate safety guard — see that
 * function's own doc comment), and `npm run test:emulator` always sets
 * that variable for this whole process, so real enforcement can never be
 * observed against the local emulator, by design. This file never
 * initializes an Admin SDK app or touches Firestore, so the env-var
 * manipulation below is safe and fully isolated from every other test
 * file (each `node --test` file runs as its own process).
 *
 * **Terminology note (Faz D.3.2.1 finding, corrected here)**: "false
 * outside the emulator" is the fail-*OPEN* (enforcement disabled) state,
 * not fail-closed — a previous test title in this exact file mislabeled
 * it "safe default, never fails open," which was backwards. Only the
 * emulator short-circuit and the strict-string-match parsing are
 * genuinely fail-closed properties; the *default absence* of
 * `ENFORCE_APP_CHECK` outside the emulator is not.
 */

test("shouldEnforceAppCheck: false whenever FIRESTORE_EMULATOR_HOST is set, even if ENFORCE_APP_CHECK=true — the emulator guard always wins (this direction is genuinely fail-closed: nothing can turn enforcement ON against the emulator)", () => {
  const savedHost = process.env.FIRESTORE_EMULATOR_HOST;
  const savedEnforce = process.env.ENFORCE_APP_CHECK;
  try {
    process.env.FIRESTORE_EMULATOR_HOST = "127.0.0.1:8080";
    process.env.ENFORCE_APP_CHECK = "true";
    assert.strictEqual(shouldEnforceAppCheck(), false);
  } finally {
    if (savedHost === undefined) delete process.env.FIRESTORE_EMULATOR_HOST;
    else process.env.FIRESTORE_EMULATOR_HOST = savedHost;
    if (savedEnforce === undefined) delete process.env.ENFORCE_APP_CHECK;
    else process.env.ENFORCE_APP_CHECK = savedEnforce;
  }
});

test("shouldEnforceAppCheck: false outside the emulator when ENFORCE_APP_CHECK is unset — this IS the fail-OPEN default (enforcement disabled), not fail-closed; the silent-misconfiguration risk this represents is what the loud-warning test below closes", () => {
  const savedHost = process.env.FIRESTORE_EMULATOR_HOST;
  const savedEnforce = process.env.ENFORCE_APP_CHECK;
  try {
    delete process.env.FIRESTORE_EMULATOR_HOST;
    delete process.env.ENFORCE_APP_CHECK;
    assert.strictEqual(shouldEnforceAppCheck(), false);
  } finally {
    if (savedHost === undefined) delete process.env.FIRESTORE_EMULATOR_HOST;
    else process.env.FIRESTORE_EMULATOR_HOST = savedHost;
    if (savedEnforce === undefined) delete process.env.ENFORCE_APP_CHECK;
    else process.env.ENFORCE_APP_CHECK = savedEnforce;
  }
});

test("shouldEnforceAppCheck: true outside the emulator when ENFORCE_APP_CHECK=true — the real production activation switch", () => {
  const savedHost = process.env.FIRESTORE_EMULATOR_HOST;
  const savedEnforce = process.env.ENFORCE_APP_CHECK;
  try {
    delete process.env.FIRESTORE_EMULATOR_HOST;
    process.env.ENFORCE_APP_CHECK = "true";
    assert.strictEqual(shouldEnforceAppCheck(), true);
  } finally {
    if (savedHost === undefined) delete process.env.FIRESTORE_EMULATOR_HOST;
    else process.env.FIRESTORE_EMULATOR_HOST = savedHost;
    if (savedEnforce === undefined) delete process.env.ENFORCE_APP_CHECK;
    else process.env.ENFORCE_APP_CHECK = savedEnforce;
  }
});

test("shouldEnforceAppCheck: fails closed (resolves false, never accidentally true) for any value other than the exact string 'true' — not fuzzy-truthy", () => {
  const savedHost = process.env.FIRESTORE_EMULATOR_HOST;
  const savedEnforce = process.env.ENFORCE_APP_CHECK;
  try {
    delete process.env.FIRESTORE_EMULATOR_HOST;
    for (const value of ["TRUE", "1", "yes", ""]) {
      process.env.ENFORCE_APP_CHECK = value;
      assert.strictEqual(shouldEnforceAppCheck(), false, `expected false for ENFORCE_APP_CHECK=${JSON.stringify(value)}`);
    }
  } finally {
    if (savedHost === undefined) delete process.env.FIRESTORE_EMULATOR_HOST;
    else process.env.FIRESTORE_EMULATOR_HOST = savedHost;
    if (savedEnforce === undefined) delete process.env.ENFORCE_APP_CHECK;
    else process.env.ENFORCE_APP_CHECK = savedEnforce;
  }
});

test("shouldEnforceAppCheck: logs a loud warning exactly once per module instance when enforcement resolves false outside the emulator — Faz D.3.2.1 closes the silent-misconfiguration gap", () => {
  const libDir = path.resolve(__dirname, "..");
  const loggerPath = require.resolve("firebase-functions/logger");
  const appCheckConfigPath = path.join(libDir, "appCheckConfig.js");

  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const loggerModule = require(loggerPath) as { warn: (...args: unknown[]) => void };
  const originalWarn = loggerModule.warn;
  let warnCount = 0;
  loggerModule.warn = (...args: unknown[]) => {
    warnCount += 1;
    return originalWarn(...args);
  };

  const savedHost = process.env.FIRESTORE_EMULATOR_HOST;
  const savedEnforce = process.env.ENFORCE_APP_CHECK;
  try {
    delete process.env.FIRESTORE_EMULATOR_HOST;
    delete process.env.ENFORCE_APP_CHECK;
    delete require.cache[appCheckConfigPath];
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const freshModule = require(appCheckConfigPath) as { shouldEnforceAppCheck: () => boolean };

    assert.strictEqual(freshModule.shouldEnforceAppCheck(), false);
    assert.strictEqual(freshModule.shouldEnforceAppCheck(), false);
    assert.strictEqual(
      warnCount,
      1,
      "expected exactly one warning across two unenforced calls on the same module instance — the once-per-cold-start guard must suppress repeats, not spam every request",
    );
  } finally {
    loggerModule.warn = originalWarn;
    delete require.cache[appCheckConfigPath];
    if (savedHost === undefined) delete process.env.FIRESTORE_EMULATOR_HOST;
    else process.env.FIRESTORE_EMULATOR_HOST = savedHost;
    if (savedEnforce === undefined) delete process.env.ENFORCE_APP_CHECK;
    else process.env.ENFORCE_APP_CHECK = savedEnforce;
  }
});

test("every App-Check-ready Function (resolveTableQrToken, openTableGuestSession, resolveTakeawayQrToken, openTakeawayGuestSession, submitTakeawayOrder, processAccountDeletion) wires the exact same shared shouldEnforceAppCheck at module-load time — no independent copy, no hardcoded boolean, no parallel config system", () => {
  const libDir = path.resolve(__dirname, "..");
  const appCheckConfigPath = path.join(libDir, "appCheckConfig.js");
  delete require.cache[appCheckConfigPath];
  // eslint-disable-next-line @typescript-eslint/no-var-requires
  const appCheckConfigModule = require(appCheckConfigPath) as {
    shouldEnforceAppCheck: () => boolean;
  };
  const original = appCheckConfigModule.shouldEnforceAppCheck;
  let callCount = 0;
  appCheckConfigModule.shouldEnforceAppCheck = () => {
    callCount += 1;
    return original();
  };

  const wiredModules = [
    "resolveTableQrToken.js",
    "openTableGuestSession.js",
    "resolveTakeawayQrToken.js",
    "openTakeawayGuestSession.js",
    "submitTakeawayOrder.js",
    "processAccountDeletion.js",
  ];
  try {
    for (const moduleFile of wiredModules) {
      const modulePath = path.join(libDir, moduleFile);
      delete require.cache[modulePath];
      require(modulePath);
    }
    assert.strictEqual(
      callCount,
      wiredModules.length,
      "every listed Function must call the same shared shouldEnforceAppCheck exactly once while constructing its onCall options — a mismatch means at least one Function is hardcoding a boolean or using a different config source",
    );
  } finally {
    appCheckConfigModule.shouldEnforceAppCheck = original;
    // Re-require every module under the real (still-cached appCheckConfig)
    // state so nothing about this process's module cache is left in the
    // monkey-patched state for any later require in this same process.
    for (const moduleFile of wiredModules) {
      const modulePath = path.join(libDir, moduleFile);
      delete require.cache[modulePath];
    }
  }
});
