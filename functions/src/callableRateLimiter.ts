import { getFirestore, Timestamp } from "firebase-admin/firestore";
import { HttpsError } from "firebase-functions/v2/https";

/**
 * Generic per-callable abuse throttle — shared by `resolveTableQrToken` and
 * `openTableGuestSession`.
 *
 * **Overrides a prior, documented, explicit decision** (`docs/decisions.md`
 * Faz D.2/D.3: "No custom rate-limiter was built, per direct instruction
 * against a general-purpose rate-limit system"; `docs/
 * table_qr_architecture.md` §7: "Rate limiting on QR resolution/session
 * creation is explicitly a backend concern, not modeled here"). That
 * decision was scoped to those two specific security-hardening phases, not
 * a permanent architectural prohibition — see ADR-049 for the explicit,
 * approved override and its reasoning.
 *
 * **Mechanism**: a Firestore-counter fixed-window limiter (no Redis/cache
 * layer exists in this stack). Each dimension (uid, IP) gets its own
 * independently-tracked bucket document in `rateLimitBuckets`, keyed
 * deterministically by `{functionName}_{dimension}_{key}` — never a
 * client-supplied id. A caller is throttled the moment *either* dimension's
 * bucket is exhausted; the other dimension's count still advances
 * independently (no shared state between them) so a uid that is fine but
 * shares an exhausted IP bucket is still correctly blocked, and vice versa.
 *
 * **Why both uid and IP, not just one**: `openTableGuestSession` requires
 * only anonymous Firebase Auth, which a script can mint fresh in a tight
 * loop — a uid-only limit is trivially bypassed that way. An IP-only limit
 * is not bypassable by uid-churn, but a busy restaurant's shared Wi-Fi/NAT
 * can legitimately put many real, distinct diners behind one IP — an
 * IP-only limit would false-positive against them. Checking both,
 * independently, means either vector alone has to go to real abuse volume
 * before it trips, while a single legitimate diner retrying a few times
 * never does.
 *
 * **Fixed window, not sliding**: simpler, and the abuse pattern this guards
 * against (scripted hammering) overwhelms a fixed window just as reliably
 * as a sliding one — the extra precision isn't worth the extra Firestore
 * reads a sliding window would need.
 */

const RATE_LIMIT_BUCKETS_COLLECTION = "rateLimitBuckets";

export interface RateLimitRule {
  readonly windowMs: number;
  readonly maxAttempts: number;
}

/**
 * Whether callable rate limiting is actually enforced for the current
 * execution.
 *
 * Deliberately the **opposite default direction** from
 * `appCheckConfig.ts`'s `shouldEnforceAppCheck()`, even though the shape
 * looks similar: App Check needs a real external provider (reCAPTCHA
 * Enterprise/Play Integrity/DeviceCheck) that isn't provisioned for this
 * project yet, so defaulting it OFF outside the emulator loses no real
 * protection today. A Firestore-counter rate limiter has no such external
 * dependency — there is no reason to ship it disabled in production, so
 * outside the emulator this is unconditionally **on**.
 *
 * Inside the Functions emulator, this defaults OFF: dozens of pre-existing
 * emulator tests (`tableGuestSession.test.ts` and every other suite that
 * calls these two callables as setup, not as a subject under test) call
 * `resolveTableQrToken`/`openTableGuestSession` repeatedly from the same
 * local IP within the same test run — enforcing real thresholds there would
 * make unrelated tests flaky/failing for a reason that has nothing to do
 * with what they test. `FORCE_CALLABLE_RATE_LIMIT_ENFORCEMENT=true` lets
 * this rate limiter's own dedicated test file turn enforcement on even
 * under the emulator, to prove the mechanism itself, without touching any
 * other test file's behavior. That same dedicated test calls
 * `enforceCallableRateLimit` directly (in-process, against the real
 * Firestore emulator) rather than through the deployed callables' own HTTP
 * endpoints — this env var only needs to reach this one test process, never
 * the separate Functions Emulator process the real callables run in, and
 * window-expiry is proven via the exported function's own `now` parameter
 * rather than a real wait.
 */
export function shouldEnforceCallableRateLimit(): boolean {
  if (process.env.FORCE_CALLABLE_RATE_LIMIT_ENFORCEMENT === "true") return true;
  if (process.env.FIRESTORE_EMULATOR_HOST) return false;
  return true;
}

function bucketDocId(
  functionName: string,
  dimension: "uid" | "ip",
  key: string,
): string {
  return `${functionName}_${dimension}_${key}`;
}

async function checkAndRecordAttempt(
  functionName: string,
  dimension: "uid" | "ip",
  key: string,
  rule: RateLimitRule,
  now: Date,
): Promise<boolean> {
  const db = getFirestore();
  const windowMs = rule.windowMs;
  const ref = db
    .collection(RATE_LIMIT_BUCKETS_COLLECTION)
    .doc(bucketDocId(functionName, dimension, key));

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const nowMs = now.getTime();

    if (!snap.exists) {
      tx.set(ref, { windowStart: Timestamp.fromDate(now), count: 1 });
      return true;
    }

    const data = snap.data()!;
    const windowStart = (data.windowStart as Timestamp).toDate().getTime();

    if (nowMs - windowStart > windowMs) {
      tx.set(ref, { windowStart: Timestamp.fromDate(now), count: 1 });
      return true;
    }

    const nextCount = (data.count as number) + 1;
    if (nextCount > rule.maxAttempts) {
      // Deliberately does not write — the window must expire naturally
      // from its original `windowStart`, not be extended by continued
      // hammering against an already-exhausted bucket.
      return false;
    }

    tx.update(ref, { count: nextCount });
    return true;
  });
}

/**
 * Enforces [uidRule]/[ipRule] for one callable invocation, throwing
 * `HttpsError('resource-exhausted', ...)` the moment either dimension is
 * exhausted. A `null` [uid] or [ip] simply skips that dimension's check —
 * `resolveTableQrToken` has no authentication requirement at all, so `uid`
 * is frequently absent; IP is still expected to be present for any real
 * HTTPS request.
 *
 * No-ops entirely when [shouldEnforceCallableRateLimit] is `false`.
 */
export async function enforceCallableRateLimit(params: {
  functionName: string;
  uid: string | null;
  ip: string | null;
  uidRule: RateLimitRule;
  ipRule: RateLimitRule;
  now?: Date;
}): Promise<void> {
  if (!shouldEnforceCallableRateLimit()) return;

  const now = params.now ?? new Date();
  const checks: Promise<boolean>[] = [];

  if (params.uid) {
    checks.push(
      checkAndRecordAttempt(params.functionName, "uid", params.uid, params.uidRule, now),
    );
  }
  if (params.ip) {
    checks.push(
      checkAndRecordAttempt(params.functionName, "ip", params.ip, params.ipRule, now),
    );
  }

  const results = await Promise.all(checks);
  if (results.some((allowed) => !allowed)) {
    throw new HttpsError(
      "resource-exhausted",
      "Too many requests. Please wait a moment before trying again.",
    );
  }
}
