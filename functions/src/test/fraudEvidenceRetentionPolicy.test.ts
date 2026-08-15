import { test } from "node:test";
import assert from "node:assert";
import {
  computeExpiresAt,
  TEST_ONLY_RETENTION_POLICY,
} from "../fraud/fraudEvidenceRetentionPolicy";

/**
 * Pure, no-emulator unit tests — FRAUD-F.0. Mirrors
 * `deliveryPaymentPolicy.test.ts`'s "no Firestore/Functions/Auth emulator
 * involved" shape: `computeExpiresAt` is a pure function of its arguments.
 */

test("computeExpiresAt: adds exactly the policy's retentionDurationMs to the given instant", () => {
  const from = new Date("2026-01-01T00:00:00.000Z");
  const policy = { id: "p1", retentionDurationMs: 1000 * 60 * 60 }; // 1h

  const expiresAt = computeExpiresAt(policy, from);

  assert.strictEqual(expiresAt.toISOString(), "2026-01-01T01:00:00.000Z");
});

test("computeExpiresAt: is deterministic — same inputs always produce the same output", () => {
  const from = new Date("2026-06-15T12:30:00.000Z");
  const policy = { id: "p2", retentionDurationMs: 42 };

  assert.strictEqual(
    computeExpiresAt(policy, from).getTime(),
    computeExpiresAt(policy, from).getTime(),
  );
});

test("TEST_ONLY_RETENTION_POLICY: is explicitly labeled non-production, not a real KVKK-approved duration", () => {
  assert.strictEqual(TEST_ONLY_RETENTION_POLICY.id, "test-only-do-not-use-in-production");
  assert.strictEqual(TEST_ONLY_RETENTION_POLICY.legalBasisVersion, null);
});
