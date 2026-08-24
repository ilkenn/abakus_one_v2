import { test } from "node:test";
import assert from "node:assert";
import { Timestamp } from "firebase-admin/firestore";
import {
  isRewardCurrentlyValid,
  parseLoyaltyRewardCatalogEntry,
  sanitizeEligibleProductIds,
  sanitizeEligibleChannels,
  sanitizeBoncukCost,
  sanitizeRewardType,
  validateValidityWindow,
  CANONICAL_COMMERCIAL_CHANNELS,
  type LoyaltyRewardCatalogEntry,
} from "../loyaltyRewardCatalog";

/**
 * Pure-function tests for `loyaltyRewardCatalog.ts` — Boncuk Loyalty
 * Program P7-B (2026-08-24). No Firestore/emulator dependency: every
 * function under test here takes plain data in, plain data out.
 */

function baseReward(overrides: Partial<LoyaltyRewardCatalogEntry> = {}): LoyaltyRewardCatalogEntry {
  const now = Timestamp.now();
  return {
    rewardId: "icecek",
    organizationId: "org-1",
    title: "İçecek",
    description: "70 Boncuk karşılığında bir içecek alın.",
    rewardType: "explicitProductSet",
    eligibleProductIds: ["prod_cocacola"],
    eligibleChannels: ["dineIn", "takeaway", "delivery", "reservationPreorder"],
    boncukCost: 70,
    active: true,
    archived: false,
    sortOrder: 0,
    version: 1,
    validFrom: null,
    validUntil: null,
    createdAt: now,
    updatedAt: now,
    ...overrides,
  };
}

// =========================================================================
// A. isRewardCurrentlyValid — server-time-only, no hidden wall-clock read
// =========================================================================

test("isRewardCurrentlyValid: active, non-archived, no validity window -> valid at any explicit now", () => {
  const reward = baseReward();
  assert.strictEqual(isRewardCurrentlyValid(reward, Timestamp.fromMillis(0)), true);
  assert.strictEqual(isRewardCurrentlyValid(reward, Timestamp.fromMillis(9_999_999_999_999)), true);
});

test("isRewardCurrentlyValid: inactive is never valid, regardless of now", () => {
  const reward = baseReward({ active: false });
  assert.strictEqual(isRewardCurrentlyValid(reward, Timestamp.now()), false);
});

test("isRewardCurrentlyValid: archived is never valid, even if active is true", () => {
  const reward = baseReward({ active: true, archived: true });
  assert.strictEqual(isRewardCurrentlyValid(reward, Timestamp.now()), false);
});

test("isRewardCurrentlyValid: before validFrom is invalid; at/after validFrom is valid — the exact same reward, only `now` differs", () => {
  const validFrom = Timestamp.fromMillis(1_000_000);
  const reward = baseReward({ validFrom });
  assert.strictEqual(isRewardCurrentlyValid(reward, Timestamp.fromMillis(999_999)), false);
  assert.strictEqual(isRewardCurrentlyValid(reward, validFrom), true);
  assert.strictEqual(isRewardCurrentlyValid(reward, Timestamp.fromMillis(1_000_001)), true);
});

test("isRewardCurrentlyValid: at/after validUntil is invalid; strictly before is valid — the exact same reward, only `now` differs", () => {
  const validUntil = Timestamp.fromMillis(2_000_000);
  const reward = baseReward({ validUntil });
  assert.strictEqual(isRewardCurrentlyValid(reward, Timestamp.fromMillis(1_999_999)), true);
  assert.strictEqual(isRewardCurrentlyValid(reward, validUntil), false);
  assert.strictEqual(isRewardCurrentlyValid(reward, Timestamp.fromMillis(2_000_001)), false);
});

// =========================================================================
// B. parseLoyaltyRewardCatalogEntry — defensive, never throws
// =========================================================================

test("parseLoyaltyRewardCatalogEntry: a well-formed document round-trips exactly", () => {
  const now = Timestamp.now();
  const raw = {
    rewardId: "icecek",
    organizationId: "org-1",
    title: "İçecek",
    description: "Açıklama",
    rewardType: "explicitProductSet",
    eligibleProductIds: ["prod_cocacola"],
    eligibleChannels: ["dineIn", "takeaway", "delivery", "reservationPreorder"],
    boncukCost: 70,
    active: true,
    archived: false,
    sortOrder: 0,
    version: 1,
    validFrom: null,
    validUntil: null,
    createdAt: now,
    updatedAt: now,
  };
  const parsed = parseLoyaltyRewardCatalogEntry(raw);
  assert.notStrictEqual(parsed, null);
  assert.deepStrictEqual(parsed, raw);
});

test("parseLoyaltyRewardCatalogEntry: undefined document returns null, never throws", () => {
  assert.strictEqual(parseLoyaltyRewardCatalogEntry(undefined), null);
});

test("parseLoyaltyRewardCatalogEntry: missing a required field returns null", () => {
  const now = Timestamp.now();
  const raw = {
    rewardId: "icecek",
    organizationId: "org-1",
    // title deliberately missing
    description: "Açıklama",
    rewardType: "explicitProductSet",
    eligibleProductIds: ["prod_cocacola"],
    eligibleChannels: ["dineIn", "takeaway", "delivery", "reservationPreorder"],
    boncukCost: 70,
    active: true,
    archived: false,
    sortOrder: 0,
    version: 1,
    validFrom: null,
    validUntil: null,
    createdAt: now,
    updatedAt: now,
  };
  assert.strictEqual(parseLoyaltyRewardCatalogEntry(raw), null);
});

test("parseLoyaltyRewardCatalogEntry: negative boncukCost returns null", () => {
  const now = Timestamp.now();
  const raw = {
    rewardId: "icecek", organizationId: "org-1", title: "İçecek", description: "x",
    rewardType: "explicitProductSet", eligibleProductIds: ["prod_cocacola"],
    eligibleChannels: ["takeaway"],
    boncukCost: -5, active: true, archived: false, sortOrder: 0, version: 1,
    validFrom: null, validUntil: null, createdAt: now, updatedAt: now,
  };
  assert.strictEqual(parseLoyaltyRewardCatalogEntry(raw), null);
});

test("parseLoyaltyRewardCatalogEntry: empty eligibleProductIds returns null", () => {
  const now = Timestamp.now();
  const raw = {
    rewardId: "icecek", organizationId: "org-1", title: "İçecek", description: "x",
    rewardType: "explicitProductSet", eligibleProductIds: [],
    eligibleChannels: ["takeaway"],
    boncukCost: 70, active: true, archived: false, sortOrder: 0, version: 1,
    validFrom: null, validUntil: null, createdAt: now, updatedAt: now,
  };
  assert.strictEqual(parseLoyaltyRewardCatalogEntry(raw), null);
});

test("parseLoyaltyRewardCatalogEntry: an invalid rewardType returns null", () => {
  const now = Timestamp.now();
  const raw = {
    rewardId: "icecek", organizationId: "org-1", title: "İçecek", description: "x",
    rewardType: "categoryEntitlement", eligibleProductIds: ["prod_cocacola"],
    eligibleChannels: ["takeaway"],
    boncukCost: 70, active: true, archived: false, sortOrder: 0, version: 1,
    validFrom: null, validUntil: null, createdAt: now, updatedAt: now,
  };
  assert.strictEqual(parseLoyaltyRewardCatalogEntry(raw), null);
});

test("parseLoyaltyRewardCatalogEntry: validFrom >= validUntil returns null", () => {
  const now = Timestamp.now();
  const raw = {
    rewardId: "icecek", organizationId: "org-1", title: "İçecek", description: "x",
    rewardType: "explicitProductSet", eligibleProductIds: ["prod_cocacola"],
    eligibleChannels: ["takeaway"],
    boncukCost: 70, active: true, archived: false, sortOrder: 0, version: 1,
    validFrom: Timestamp.fromMillis(2_000_000), validUntil: Timestamp.fromMillis(1_000_000),
    createdAt: now, updatedAt: now,
  };
  assert.strictEqual(parseLoyaltyRewardCatalogEntry(raw), null);
});

// =========================================================================
// C. Sanitizers
// =========================================================================

test("sanitizeBoncukCost: rejects zero, negative, and non-integer values", () => {
  assert.throws(() => sanitizeBoncukCost(0));
  assert.throws(() => sanitizeBoncukCost(-1));
  assert.throws(() => sanitizeBoncukCost(1.5));
  assert.throws(() => sanitizeBoncukCost("70"));
  assert.strictEqual(sanitizeBoncukCost(70), 70);
});

test("sanitizeEligibleProductIds: rejects an empty array", () => {
  assert.throws(() => sanitizeEligibleProductIds([]));
});

test("sanitizeEligibleProductIds: de-duplicates while preserving first-seen order", () => {
  const result = sanitizeEligibleProductIds(["a", "b", "a"]);
  assert.deepStrictEqual(result, ["a", "b"]);
});

test("sanitizeRewardType: only 'explicitProductSet' is accepted this phase", () => {
  assert.strictEqual(sanitizeRewardType("explicitProductSet"), "explicitProductSet");
  assert.throws(() => sanitizeRewardType("categoryEntitlement"));
  assert.throws(() => sanitizeRewardType(123));
});

// =========================================================================
// D. sanitizeEligibleChannels — P7-C.1 (2026-08-24)
// =========================================================================

test("sanitizeEligibleChannels: a single valid channel is accepted", () => {
  assert.deepStrictEqual(sanitizeEligibleChannels(["takeaway"]), ["takeaway"]);
});

test("sanitizeEligibleChannels: multiple valid channels are accepted, normalized into canonical order", () => {
  assert.deepStrictEqual(
    sanitizeEligibleChannels(["delivery", "dineIn"]),
    ["dineIn", "delivery"],
  );
});

test("sanitizeEligibleChannels: an empty array is rejected", () => {
  assert.throws(() => sanitizeEligibleChannels([]));
});

test("sanitizeEligibleChannels: missing/non-array input is rejected", () => {
  assert.throws(() => sanitizeEligibleChannels(undefined));
  assert.throws(() => sanitizeEligibleChannels(null));
  assert.throws(() => sanitizeEligibleChannels("takeaway"));
});

test("sanitizeEligibleChannels: an unsupported channel value is rejected", () => {
  assert.throws(() => sanitizeEligibleChannels(["takeaway", "drone"]));
  assert.throws(() => sanitizeEligibleChannels(["pos"]));
});

test("sanitizeEligibleChannels: duplicate channels are normalized deterministically, not rejected — same input order or reordered/duplicated produces the identical stored array", () => {
  const fromDuplicates = sanitizeEligibleChannels(["takeaway", "takeaway", "delivery"]);
  const fromReorderedNoDuplicates = sanitizeEligibleChannels(["delivery", "takeaway"]);
  assert.deepStrictEqual(fromDuplicates, fromReorderedNoDuplicates);
  assert.deepStrictEqual(fromDuplicates, ["takeaway", "delivery"]);
});

test("sanitizeEligibleChannels: all four canonical channels together round-trip in canonical order", () => {
  assert.deepStrictEqual(
    sanitizeEligibleChannels(["reservationPreorder", "takeaway", "dineIn", "delivery"]),
    [...CANONICAL_COMMERCIAL_CHANNELS],
  );
});

test("validateValidityWindow: validFrom must be strictly before validUntil when both present", () => {
  assert.throws(() =>
    validateValidityWindow(Timestamp.fromMillis(2_000_000), Timestamp.fromMillis(1_000_000)),
  );
  assert.throws(() =>
    validateValidityWindow(Timestamp.fromMillis(1_000_000), Timestamp.fromMillis(1_000_000)),
  );
  assert.doesNotThrow(() =>
    validateValidityWindow(Timestamp.fromMillis(1_000_000), Timestamp.fromMillis(2_000_000)),
  );
  assert.doesNotThrow(() => validateValidityWindow(null, null));
});
