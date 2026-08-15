import { defineBoolean } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";

/**
 * Shared App Check enforcement toggle — Faz D.3 (§15, closing the
 * REQUIRED finding Faz D.2 left open), hardened Faz D.3.2.1 (Account
 * Deletion Authorization + App Check Fail-Safe Audit).
 *
 * `onCall`'s `enforceAppCheck` option is a real, working Cloud Functions
 * feature; the only reason it isn't simply hardcoded `true` here is that
 * doing so would break every emulator/local-dev test in this repository,
 * none of which mints a real App Check token — mirrors
 * `FirebaseAppCheckService`'s own Dart-side "unactivated until a
 * reCAPTCHA Enterprise site key is configured" caveat, applied to the
 * Functions side.
 *
 * **Two genuinely different fail-safe properties, not one — do not
 * conflate them (Faz D.3.2.1 finding: an earlier report mislabeled the
 * second one)**:
 *
 * 1. **The emulator short-circuit is fail-*closed* in the sense that
 *    matters for it**: it unconditionally forces enforcement OFF whenever
 *    `FIRESTORE_EMULATOR_HOST` is present, *regardless* of
 *    `ENFORCE_APP_CHECK`'s value — nothing can accidentally turn
 *    enforcement on against a local emulator, which is the property this
 *    guard exists to guarantee (a local run must never depend on real App
 *    Check tokens existing).
 * 2. **Outside the emulator, the *default* (no `ENFORCE_APP_CHECK` value
 *    present) resolves to `false` — enforcement OFF.** This is **fail-
 *    OPEN, not fail-closed**, and must never be described otherwise: a
 *    deployment that forgets to set this parameter is not blocked, not
 *    warned loudly by default in the Firebase Console today, and simply
 *    runs every App-Check-ready Function completely unenforced, silently.
 *    That silence is the actual gap this hardening closes (see below) —
 *    calling the pre-hardening behavior "fail-closed" anywhere (docs, test
 *    names, comments) was a real mistake, not a stylistic one, and every
 *    such instance was corrected as part of this same task.
 *
 * **Firebase-native config, not a raw env var (Faz D.3.2.1)**:
 * `ENFORCE_APP_CHECK` is now declared as a real Cloud Functions v2
 * Parameter (`firebase-functions/params`'s `defineBoolean`) rather than
 * read directly off `process.env`. This is the actual, documented Firebase
 * mechanism for deployment configuration — declared parameters are
 * discoverable via `firebase functions:params:list` and the Firebase
 * Console, and are what the CLI resolves from a project's `.env.<project>`
 * file at deploy time — instead of an invisible, undocumented raw
 * environment variable nobody would think to go looking for. `.value()`'s
 * runtime resolution is intentionally identical to the previous manual
 * check (`process.env.ENFORCE_APP_CHECK === "true"`, exactly what
 * `BooleanParam.runtimeValue()` itself does) — this migration changes
 * *visibility*, not *parsing behavior*: a value that is not the literal
 * string `"true"` still resolves to `false`, deliberately (fails closed
 * against a typo like `"TRUE"`/`"1"`/`"yes"` silently *enabling*
 * enforcement it shouldn't — that direction of failure would be worse:
 * genuine clients locked out with no App Check provider actually
 * configured yet).
 *
 * **The silent-misconfiguration gap itself is closed by a loud runtime
 * warning, not a deploy-time hard failure**: outside the emulator, if
 * enforcement resolves to `false`, this module logs a single structured
 * `logger.warn` (Firebase's own `firebase-functions/logger`, surfaced in
 * Cloud Logging/the Firebase Console — not a `console.log` call this
 * project invented) once per cold start, naming exactly which condition
 * is true. A hard failure (throwing at module load, refusing to serve any
 * request) was considered and deliberately rejected for this task's scope
 * — it would make this Function (and every other App-Check-ready
 * Function, since they all share this one config) **entirely undeployable
 * until a real App Check provider is provisioned for every platform**,
 * which is a materially larger, riskier decision than "close the account-
 * deletion authorization gap and the reported App Check inconsistency" —
 * this project's App Check providers are not provisioned yet (per
 * `FirebaseAppCheckService`'s own doc comment), so a hard failure today
 * would immediately break every deployment, not just a misconfigured one.
 * Recorded as a RECOMMENDED follow-up (see this task's own report) for
 * once providers exist and a real production rollout is imminent — at
 * that point, promoting this parameter to one with no `default` (so the
 * Firebase CLI prompts/fails at `deploy` time instead of only logging at
 * runtime) is the natural next step, not implemented here since it cannot
 * be safely validated against a real deploy from this environment.
 *
 * Production activation is a deployment-config change, not a code change:
 * set `ENFORCE_APP_CHECK=true` in the target project's `.env.<project>`
 * file (or via `firebase functions:config:set`/an interactive `firebase
 * deploy` prompt, since this is now a declared Parameter) once a real
 * reCAPTCHA Enterprise (web) / Play Integrity (Android) / DeviceCheck
 * (iOS) App Check provider is actually provisioned for the target Firebase
 * project — every App-Check-ready Function then enforces it with no
 * further code change.
 */
const enforceAppCheckParam = defineBoolean("ENFORCE_APP_CHECK", {
  default: false,
  description:
    "Enforce App Check on every App-Check-ready callable Function " +
    "(resolveTableQrToken, openTableGuestSession, resolveTakeawayQrToken, " +
    "openTakeawayGuestSession, submitTakeawayOrder, " +
    "processAccountDeletion). Never enforced under the local emulator " +
    "regardless of this value. Requires a real App Check provider " +
    "(reCAPTCHA Enterprise/Play Integrity/DeviceCheck) to already be " +
    "provisioned for the target project before setting this to true, or " +
    "genuine clients get locked out too.",
});

let hasWarnedThisColdStart = false;

export function shouldEnforceAppCheck(): boolean {
  if (process.env.FIRESTORE_EMULATOR_HOST) return false;

  const enforced = enforceAppCheckParam.value();
  if (!enforced && !hasWarnedThisColdStart) {
    hasWarnedThisColdStart = true;
    logger.warn(
      "[appCheckConfig] App Check enforcement is OFF outside the local " +
        "emulator (ENFORCE_APP_CHECK is not \"true\"). Every App-Check-" +
        "ready Function is currently reachable without a valid App Check " +
        "token. If this is a real (non-emulator) deployment, this is a " +
        "silent security gap, not a benign default — set " +
        "ENFORCE_APP_CHECK=true once a real App Check provider is " +
        "provisioned for this project.",
    );
  }
  return enforced;
}
