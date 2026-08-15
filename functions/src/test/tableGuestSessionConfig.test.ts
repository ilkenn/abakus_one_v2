import { test } from "node:test";
import assert from "node:assert";
import {
  isTableGuestSessionActive,
  TABLE_GUEST_SESSION_TTL_HOURS,
  TABLE_GUEST_SESSION_TTL_MS,
} from "../tableGuestSessionConfig";

/**
 * Pure, boundary-precise unit tests for `tableGuestSessionConfig.ts` —
 * Table Guest Session Phase 1/2 review fix. No Firestore/Functions/Auth
 * emulator involved (run via plain `npm test`, not `npm run
 * test:emulator`) — `isTableGuestSessionActive` is a pure function of its
 * two arguments.
 *
 * **Honesty note**: `isTableGuestSessionActive` has no real caller yet in
 * this phase (`openTableGuestSession` only ever creates a brand-new
 * session; nothing yet re-reads an existing one to decide whether it's
 * still usable — that's Phase 3's `orders` Security Rule). These tests
 * verify the exact boundary logic Phase 3 will consume, ahead of that
 * consumer existing — they do not claim anything is currently being
 * rejected end-to-end by this function today.
 */

test("config: TABLE_GUEST_SESSION_TTL_MS is derived from TABLE_GUEST_SESSION_TTL_HOURS, not an independent magic number", () => {
  assert.strictEqual(
    TABLE_GUEST_SESSION_TTL_MS,
    TABLE_GUEST_SESSION_TTL_HOURS * 60 * 60 * 1000,
  );
});

test("config: the default TTL is hour-scale (not minutes, not days) absent an environment override", () => {
  // This process was not launched with TABLE_GUEST_SESSION_TTL_HOURS set,
  // so the module-level default applies.
  assert.ok(TABLE_GUEST_SESSION_TTL_HOURS >= 1);
  assert.ok(TABLE_GUEST_SESSION_TTL_HOURS <= 24);
});

test("isTableGuestSessionActive: a freshly created session (expiresAt = now + TTL) is active", () => {
  const now = new Date();
  const session = {
    status: "active",
    expiresAt: new Date(now.getTime() + TABLE_GUEST_SESSION_TTL_MS),
  };

  assert.strictEqual(isTableGuestSessionActive(session, now), true);
});

test("isTableGuestSessionActive: one millisecond before expiresAt is still active", () => {
  const expiresAt = new Date("2026-01-01T12:00:00.000Z");
  const oneMsBefore = new Date(expiresAt.getTime() - 1);

  assert.strictEqual(
    isTableGuestSessionActive({ status: "active", expiresAt }, oneMsBefore),
    true,
  );
});

test("isTableGuestSessionActive: exactly at the expiresAt boundary is NOT active (strict > required, not >=)", () => {
  const expiresAt = new Date("2026-01-01T12:00:00.000Z");

  assert.strictEqual(
    isTableGuestSessionActive({ status: "active", expiresAt }, expiresAt),
    false,
  );
});

test("isTableGuestSessionActive: one millisecond after expiresAt is expired — rejected", () => {
  const expiresAt = new Date("2026-01-01T12:00:00.000Z");
  const oneMsAfter = new Date(expiresAt.getTime() + 1);

  assert.strictEqual(
    isTableGuestSessionActive({ status: "active", expiresAt }, oneMsAfter),
    false,
  );
});

test("isTableGuestSessionActive: accepts a Firestore Timestamp-shaped value (anything with .toDate()), not only a raw Date", () => {
  const now = new Date();
  const futureDate = new Date(now.getTime() + TABLE_GUEST_SESSION_TTL_MS);
  const timestampLike = { toDate: () => futureDate };

  assert.strictEqual(
    isTableGuestSessionActive({ status: "active", expiresAt: timestampLike }, now),
    true,
  );
});

for (const status of ["closed", "revoked", "expired"]) {
  test(`isTableGuestSessionActive: a session with status '${status}' is never active, even with a future expiresAt`, () => {
    const now = new Date();
    const farFuture = new Date(now.getTime() + TABLE_GUEST_SESSION_TTL_MS * 10);

    assert.strictEqual(
      isTableGuestSessionActive({ status, expiresAt: farFuture }, now),
      false,
    );
  });
}
