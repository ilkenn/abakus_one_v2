import { test } from "node:test";
import assert from "node:assert";
import {
  isTakeawayGuestSessionActive,
  TAKEAWAY_GUEST_SESSION_TTL_MINUTES,
  TAKEAWAY_GUEST_SESSION_TTL_MS,
} from "../takeawayGuestSessionConfig";

/**
 * Pure, boundary-precise unit tests for `takeawayGuestSessionConfig.ts` —
 * Faz D.2 (Gel Al QR + Guest Session Backend). No Firestore/Functions/Auth
 * emulator involved (run via plain `npm test`) — `isTakeawayGuestSessionActive`
 * is a pure function of its two arguments, mirroring
 * `tableGuestSessionConfig.test.ts`'s exact structure for the same reason.
 */

test("config: TAKEAWAY_GUEST_SESSION_TTL_MS is derived from TAKEAWAY_GUEST_SESSION_TTL_MINUTES, not an independent magic number", () => {
  assert.strictEqual(
    TAKEAWAY_GUEST_SESSION_TTL_MS,
    TAKEAWAY_GUEST_SESSION_TTL_MINUTES * 60 * 1000,
  );
});

test("config: the default TTL is minute-scale (checkout-length, not hour-scale like the dine-in table session) absent an environment override", () => {
  // This process was not launched with TAKEAWAY_GUEST_SESSION_TTL_MINUTES
  // set, so the module-level default (30 minutes) applies.
  assert.ok(TAKEAWAY_GUEST_SESSION_TTL_MINUTES >= 10);
  assert.ok(TAKEAWAY_GUEST_SESSION_TTL_MINUTES <= 60);
});

test("isTakeawayGuestSessionActive: a freshly created session (expiresAt = now + TTL) is active", () => {
  const now = new Date();
  const session = {
    status: "active",
    expiresAt: new Date(now.getTime() + TAKEAWAY_GUEST_SESSION_TTL_MS),
  };

  assert.strictEqual(isTakeawayGuestSessionActive(session, now), true);
});

test("isTakeawayGuestSessionActive: one millisecond before expiresAt is still active", () => {
  const expiresAt = new Date("2026-01-01T12:00:00.000Z");
  const oneMsBefore = new Date(expiresAt.getTime() - 1);

  assert.strictEqual(
    isTakeawayGuestSessionActive({ status: "active", expiresAt }, oneMsBefore),
    true,
  );
});

test("isTakeawayGuestSessionActive: exactly at the expiresAt boundary is NOT active (strict > required, not >=)", () => {
  const expiresAt = new Date("2026-01-01T12:00:00.000Z");

  assert.strictEqual(
    isTakeawayGuestSessionActive({ status: "active", expiresAt }, expiresAt),
    false,
  );
});

test("isTakeawayGuestSessionActive: one millisecond after expiresAt is expired — rejected", () => {
  const expiresAt = new Date("2026-01-01T12:00:00.000Z");
  const oneMsAfter = new Date(expiresAt.getTime() + 1);

  assert.strictEqual(
    isTakeawayGuestSessionActive({ status: "active", expiresAt }, oneMsAfter),
    false,
  );
});

test("isTakeawayGuestSessionActive: accepts a Firestore Timestamp-shaped value (anything with .toDate()), not only a raw Date", () => {
  const now = new Date();
  const futureDate = new Date(now.getTime() + TAKEAWAY_GUEST_SESSION_TTL_MS);
  const timestampLike = { toDate: () => futureDate };

  assert.strictEqual(
    isTakeawayGuestSessionActive({ status: "active", expiresAt: timestampLike }, now),
    true,
  );
});

for (const status of ["closed", "revoked", "expired"]) {
  test(`isTakeawayGuestSessionActive: a session with status '${status}' is never active, even with a future expiresAt`, () => {
    const now = new Date();
    const farFuture = new Date(now.getTime() + TAKEAWAY_GUEST_SESSION_TTL_MS * 10);

    assert.strictEqual(
      isTakeawayGuestSessionActive({ status, expiresAt: farFuture }, now),
      false,
    );
  });
}
