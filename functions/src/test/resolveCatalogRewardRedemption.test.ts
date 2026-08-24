import { test } from "node:test";
import assert from "node:assert";
import { Timestamp } from "firebase-admin/firestore";
import { resolveCatalogRewardRedemption } from "../resolveCatalogRewardRedemption";
import type { LoyaltyRewardCatalogEntry } from "../loyaltyRewardCatalog";

/**
 * Pure-function tests for `resolveCatalogRewardRedemption` — Boncuk
 * Loyalty Program P7-B (2026-08-24). No Firestore/emulator dependency —
 * every fixture below is a hand-built `LoyaltyRewardCatalogEntry`, exactly
 * as a real caller would have already loaded it via
 * `loadLoyaltyRewardForRedemption` before calling this function.
 */

function reward(overrides: Partial<LoyaltyRewardCatalogEntry> = {}): LoyaltyRewardCatalogEntry {
  const now = Timestamp.now();
  return {
    rewardId: "citirti-bowl",
    organizationId: "org-1",
    title: "Çıtırtı Bowl",
    description: "420 Boncuk karşılığında bir Çıtırtı Bowl alın.",
    rewardType: "explicitProductSet",
    eligibleProductIds: ["prod_citirti_bowl"],
    eligibleChannels: ["dineIn", "takeaway", "delivery", "reservationPreorder"],
    boncukCost: 420,
    active: true,
    archived: false,
    sortOrder: 1,
    version: 3, // deliberately not 1 — proves the resolver echoes the REAL loaded version, not a hardcoded one.
    validFrom: null,
    validUntil: null,
    createdAt: now,
    updatedAt: now,
    ...overrides,
  };
}

const NOW = new Date("2026-08-24T12:00:00.000Z");

test("resolver: an eligible product with sufficient balance succeeds, snapshot carries only server-resolved values", () => {
  const result = resolveCatalogRewardRedemption({
    reward: reward(),
    now: NOW,
    organizationId: "org-1",
    orderChannel: "takeaway",
    requestedProductId: "prod_citirti_bowl",
    spendableBalance: 500,
  });
  assert.strictEqual(result.status, "ok");
  if (result.status !== "ok") return;
  assert.deepStrictEqual(result.snapshot, {
    rewardId: "citirti-bowl",
    rewardVersion: 3,
    title: "Çıtırtı Bowl",
    boncukCost: 420,
    redeemedProductId: "prod_citirti_bowl",
  });
});

test("resolver: the snapshot's boncukCost/title/rewardVersion always come from the loaded reward, never invented or client-influenced — proven by varying the reward fixture, not any caller input", () => {
  const result = resolveCatalogRewardRedemption({
    reward: reward({ boncukCost: 999, title: "Different Title", version: 7 }),
    now: NOW,
    organizationId: "org-1",
    orderChannel: "takeaway",
    requestedProductId: "prod_citirti_bowl",
    spendableBalance: 999,
  });
  assert.strictEqual(result.status, "ok");
  if (result.status !== "ok") return;
  assert.strictEqual(result.snapshot.boncukCost, 999);
  assert.strictEqual(result.snapshot.title, "Different Title");
  assert.strictEqual(result.snapshot.rewardVersion, 7);
});

test("resolver: a product NOT in eligibleProductIds is rejected", () => {
  const result = resolveCatalogRewardRedemption({
    reward: reward(),
    now: NOW,
    organizationId: "org-1",
    orderChannel: "takeaway",
    requestedProductId: "prod_falafel_bowl",
    spendableBalance: 500,
  });
  assert.strictEqual(result.status, "product-not-eligible");
});

test("resolver: insufficient spendableBalance is rejected with the exact required/available figures", () => {
  const result = resolveCatalogRewardRedemption({
    reward: reward({ boncukCost: 420 }),
    now: NOW,
    organizationId: "org-1",
    orderChannel: "takeaway",
    requestedProductId: "prod_citirti_bowl",
    spendableBalance: 100,
  });
  assert.strictEqual(result.status, "insufficient-balance");
  if (result.status !== "insufficient-balance") return;
  assert.strictEqual(result.requiredBoncuk, 420);
  assert.strictEqual(result.availableBoncuk, 100);
});

test("resolver: exact-balance boundary (spendableBalance === boncukCost) succeeds", () => {
  const result = resolveCatalogRewardRedemption({
    reward: reward({ boncukCost: 420 }),
    now: NOW,
    organizationId: "org-1",
    orderChannel: "takeaway",
    requestedProductId: "prod_citirti_bowl",
    spendableBalance: 420,
  });
  assert.strictEqual(result.status, "ok");
});

test("resolver: an organizationId mismatch is rejected", () => {
  const result = resolveCatalogRewardRedemption({
    reward: reward({ organizationId: "org-1" }),
    now: NOW,
    organizationId: "org-2",
    orderChannel: "takeaway",
    requestedProductId: "prod_citirti_bowl",
    spendableBalance: 500,
  });
  assert.strictEqual(result.status, "organization-mismatch");
});

test("resolver: an inactive reward is rejected as not-currently-valid", () => {
  const result = resolveCatalogRewardRedemption({
    reward: reward({ active: false }),
    now: NOW,
    organizationId: "org-1",
    orderChannel: "takeaway",
    requestedProductId: "prod_citirti_bowl",
    spendableBalance: 500,
  });
  assert.strictEqual(result.status, "reward-not-currently-valid");
});

test("resolver: an archived reward is rejected as not-currently-valid", () => {
  const result = resolveCatalogRewardRedemption({
    reward: reward({ archived: true }),
    now: NOW,
    organizationId: "org-1",
    orderChannel: "takeaway",
    requestedProductId: "prod_citirti_bowl",
    spendableBalance: 500,
  });
  assert.strictEqual(result.status, "reward-not-currently-valid");
});

test("resolver: a reward whose validUntil has already passed is rejected as not-currently-valid", () => {
  const result = resolveCatalogRewardRedemption({
    reward: reward({ validUntil: Timestamp.fromDate(new Date("2026-01-01T00:00:00.000Z")) }),
    now: NOW,
    organizationId: "org-1",
    orderChannel: "takeaway",
    requestedProductId: "prod_citirti_bowl",
    spendableBalance: 500,
  });
  assert.strictEqual(result.status, "reward-not-currently-valid");
});

test("resolver: reward === null is reward-not-found", () => {
  const result = resolveCatalogRewardRedemption({
    reward: null,
    now: NOW,
    organizationId: "org-1",
    orderChannel: "takeaway",
    requestedProductId: "prod_citirti_bowl",
    spendableBalance: 500,
  });
  assert.strictEqual(result.status, "reward-not-found");
});

test("resolver: product-eligibility check precedes the balance check — an ineligible product is rejected even with an enormous balance", () => {
  const result = resolveCatalogRewardRedemption({
    reward: reward(),
    now: NOW,
    organizationId: "org-1",
    orderChannel: "takeaway",
    requestedProductId: "prod_something_else",
    spendableBalance: 1_000_000,
  });
  assert.strictEqual(result.status, "product-not-eligible");
});

// =========================================================================
// Channel eligibility — Boncuk Loyalty P7-C.1 (2026-08-24)
// =========================================================================

test("resolver: a reward eligible for the requested channel succeeds", () => {
  const result = resolveCatalogRewardRedemption({
    reward: reward({ eligibleChannels: ["takeaway"] }),
    now: NOW,
    organizationId: "org-1",
    orderChannel: "takeaway",
    requestedProductId: "prod_citirti_bowl",
    spendableBalance: 500,
  });
  assert.strictEqual(result.status, "ok");
});

test("resolver: a reward eligible for MULTIPLE channels succeeds for any one of them", () => {
  const multiChannelReward = reward({ eligibleChannels: ["dineIn", "takeaway", "delivery"] });
  for (const orderChannel of ["dineIn", "takeaway", "delivery"] as const) {
    const result = resolveCatalogRewardRedemption({
      reward: multiChannelReward,
      now: NOW,
      organizationId: "org-1",
      orderChannel,
      requestedProductId: "prod_citirti_bowl",
      spendableBalance: 500,
    });
    assert.strictEqual(result.status, "ok", `expected ok for channel "${orderChannel}"`);
  }
});

test("resolver: a reward NOT eligible for the requested channel is rejected as channel-not-eligible — even with an eligible product and sufficient balance", () => {
  const result = resolveCatalogRewardRedemption({
    reward: reward({ eligibleChannels: ["delivery", "reservationPreorder"] }),
    now: NOW,
    organizationId: "org-1",
    orderChannel: "takeaway",
    requestedProductId: "prod_citirti_bowl",
    spendableBalance: 500,
  });
  assert.strictEqual(result.status, "channel-not-eligible");
});

test("resolver: channel eligibility is checked before product eligibility — a wrong-channel reward is rejected as channel-not-eligible even for an ineligible product", () => {
  const result = resolveCatalogRewardRedemption({
    reward: reward({ eligibleChannels: ["delivery"] }),
    now: NOW,
    organizationId: "org-1",
    orderChannel: "takeaway",
    requestedProductId: "prod_something_else",
    spendableBalance: 500,
  });
  assert.strictEqual(result.status, "channel-not-eligible");
});
