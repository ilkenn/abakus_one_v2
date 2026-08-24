import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import {
  createLoyaltyReward,
  updateLoyaltyRewardByCreatingNextVersion,
  setLoyaltyRewardActive,
  archiveLoyaltyReward,
} from "../loyaltyRewardCatalogAdminService";
import {
  LOYALTY_REWARD_CATALOG_COLLECTION,
  LOYALTY_REWARD_CATALOG_VERSIONS_COLLECTION,
  loyaltyRewardCatalogVersionDocId,
} from "../loyaltyRewardCatalog";

/**
 * Emulator-backed tests for `loyaltyRewardCatalogAdminService.ts` — Boncuk
 * Loyalty Program P7-B (2026-08-24). These are plain trusted functions
 * (not `onCall` callables), so this file calls them directly against a
 * real Admin-SDK-connected `Firestore` instance, exactly the way the local
 * dev-seed script and (in a future phase) an Admin-authorized callable
 * both would.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";

let app: admin.app.App;
before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});
after(async () => {
  await app.delete();
});

const db = () => admin.firestore();

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function seedOrg(organizationId: string, isActive = true) {
  await db().collection("organizations").doc(organizationId).set({ name: "Test Org", isActive });
}

async function seedProduct(productId: string, organizationId: string) {
  await db().collection("menuProducts").doc(productId).set({
    organizationId,
    restaurantId: "restaurant-x",
    categoryId: "cat_test",
    name: "Test Product",
    basePriceMinorUnits: 10000,
    isAvailable: true,
    modifierGroups: [],
    channelPriceOverrides: {},
  });
}

async function rewardDoc(rewardId: string) {
  return (await db().collection(LOYALTY_REWARD_CATALOG_COLLECTION).doc(rewardId).get()).data();
}

async function versionDoc(rewardId: string, version: number) {
  return (
    await db()
      .collection(LOYALTY_REWARD_CATALOG_VERSIONS_COLLECTION)
      .doc(loyaltyRewardCatalogVersionDocId(rewardId, version))
      .get()
  ).data();
}

function validInput(organizationId: string, rewardId: string, eligibleProductIds: string[]) {
  return {
    organizationId,
    rewardId,
    title: "Test Reward",
    description: "Bir test ödülü.",
    rewardType: "explicitProductSet" as const,
    eligibleProductIds,
    eligibleChannels: ["dineIn", "takeaway", "delivery", "reservationPreorder"],
    boncukCost: 100,
    sortOrder: 0,
  };
}

// =========================================================================
// A. createLoyaltyReward
// =========================================================================

test("createLoyaltyReward: valid input creates version 1, live doc and version doc match", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);

  const result = await createLoyaltyReward(db(), validInput(orgId, rewardId, [productId]));
  assert.strictEqual(result.created, true);
  assert.strictEqual(result.version, 1);
  assert.strictEqual(result.rewardId, rewardId);

  const live = await rewardDoc(rewardId);
  assert.strictEqual(live?.active, true);
  assert.strictEqual(live?.archived, false);
  assert.strictEqual(live?.version, 1);
  assert.deepStrictEqual(live?.eligibleProductIds, [productId]);
  assert.strictEqual(live?.boncukCost, 100);

  const v1 = await versionDoc(rewardId, 1);
  assert.strictEqual(v1?.version, 1);
  assert.strictEqual(v1?.boncukCost, 100);
  assert.deepStrictEqual(v1?.eligibleProductIds, [productId]);
  assert.strictEqual(v1?.title, "Test Reward");
});

test("createLoyaltyReward: a nonexistent eligible product is rejected, no doc created", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  await seedOrg(orgId);

  await assert.rejects(() =>
    createLoyaltyReward(db(), validInput(orgId, rewardId, ["prod_does_not_exist"])),
  );
  assert.strictEqual(await rewardDoc(rewardId), undefined);
});

test("createLoyaltyReward: an eligible product belonging to a DIFFERENT organization is rejected", async () => {
  const orgId = nextId("org");
  const otherOrgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedOrg(otherOrgId);
  await seedProduct(productId, otherOrgId); // belongs to the OTHER org

  await assert.rejects(() => createLoyaltyReward(db(), validInput(orgId, rewardId, [productId])));
  assert.strictEqual(await rewardDoc(rewardId), undefined);
});

test("createLoyaltyReward: boncukCost must be a positive integer — zero, negative, fractional all rejected", async () => {
  const orgId = nextId("org");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);

  for (const boncukCost of [0, -5, 1.5]) {
    const rewardId = nextId("reward");
    await assert.rejects(() =>
      createLoyaltyReward(db(), { ...validInput(orgId, rewardId, [productId]), boncukCost }),
    );
  }
});

test("createLoyaltyReward: empty eligibleProductIds is rejected", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  await seedOrg(orgId);

  await assert.rejects(() => createLoyaltyReward(db(), validInput(orgId, rewardId, [])));
});

test("createLoyaltyReward: an inactive organization is rejected", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId, false);
  await seedProduct(productId, orgId);

  await assert.rejects(() => createLoyaltyReward(db(), validInput(orgId, rewardId, [productId])));
});

test("createLoyaltyReward: corrupt/malformed input (missing title) fails closed", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);

  const input = validInput(orgId, rewardId, [productId]) as Record<string, unknown>;
  delete input.title;
  await assert.rejects(() => createLoyaltyReward(db(), input as never));
});

test("createLoyaltyReward: validFrom must be strictly before validUntil", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);

  await assert.rejects(() =>
    createLoyaltyReward(db(), {
      ...validInput(orgId, rewardId, [productId]),
      validFrom: new Date("2026-06-01"),
      validUntil: new Date("2026-01-01"),
    }),
  );
});

test("createLoyaltyReward: idempotent — calling twice with the same rewardId returns created:true then created:false, no duplicate version doc", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);
  const input = validInput(orgId, rewardId, [productId]);

  const first = await createLoyaltyReward(db(), input);
  const second = await createLoyaltyReward(db(), input);
  assert.strictEqual(first.created, true);
  assert.strictEqual(second.created, false);
  assert.strictEqual(first.version, 1);
  assert.strictEqual(second.version, 1);

  const versionsSnap = await db()
    .collection(LOYALTY_REWARD_CATALOG_VERSIONS_COLLECTION)
    .where("rewardId", "==", rewardId)
    .get();
  assert.strictEqual(versionsSnap.size, 1, "exactly one version-1 document must exist, never a duplicate");
});

// =========================================================================
// B. updateLoyaltyRewardByCreatingNextVersion
// =========================================================================

test("updateLoyaltyRewardByCreatingNextVersion: creates V2, live doc reflects the change, V1 is untouched", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);
  await createLoyaltyReward(db(), validInput(orgId, rewardId, [productId]));

  const v1Before = await versionDoc(rewardId, 1);

  const result = await updateLoyaltyRewardByCreatingNextVersion(db(), orgId, rewardId, {
    boncukCost: 250,
  });
  assert.strictEqual(result.version, 2);

  const live = await rewardDoc(rewardId);
  assert.strictEqual(live?.version, 2);
  assert.strictEqual(live?.boncukCost, 250);
  // Untouched fields carry over from the current definition.
  assert.strictEqual(live?.title, "Test Reward");
  assert.deepStrictEqual(live?.eligibleProductIds, [productId]);

  const v2 = await versionDoc(rewardId, 2);
  assert.strictEqual(v2?.boncukCost, 250);

  const v1After = await versionDoc(rewardId, 1);
  assert.deepStrictEqual(v1After, v1Before, "V1 must remain byte-for-byte unchanged after the V2 update");
});

test("updateLoyaltyRewardByCreatingNextVersion: version is strictly monotonic across multiple updates", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);
  await createLoyaltyReward(db(), validInput(orgId, rewardId, [productId]));

  const second = await updateLoyaltyRewardByCreatingNextVersion(db(), orgId, rewardId, { boncukCost: 200 });
  const third = await updateLoyaltyRewardByCreatingNextVersion(db(), orgId, rewardId, { boncukCost: 300 });
  assert.strictEqual(second.version, 2);
  assert.strictEqual(third.version, 3);

  const live = await rewardDoc(rewardId);
  assert.strictEqual(live?.version, 3);
  assert.strictEqual(live?.boncukCost, 300);
});

test("updateLoyaltyRewardByCreatingNextVersion: updating eligibleProductIds re-validates the new products", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);
  await createLoyaltyReward(db(), validInput(orgId, rewardId, [productId]));

  await assert.rejects(() =>
    updateLoyaltyRewardByCreatingNextVersion(db(), orgId, rewardId, {
      eligibleProductIds: ["prod_does_not_exist"],
    }),
  );
  // Rejected update must not have created a V2.
  const live = await rewardDoc(rewardId);
  assert.strictEqual(live?.version, 1);
});

test("updateLoyaltyRewardByCreatingNextVersion: changing eligibleChannels creates V2; V1 remains byte-for-byte unchanged (P7-C.1)", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);
  await createLoyaltyReward(db(), validInput(orgId, rewardId, [productId]));

  const v1Before = await versionDoc(rewardId, 1);
  assert.deepStrictEqual(v1Before?.eligibleChannels, [
    "dineIn",
    "takeaway",
    "delivery",
    "reservationPreorder",
  ]);

  const result = await updateLoyaltyRewardByCreatingNextVersion(db(), orgId, rewardId, {
    eligibleChannels: ["takeaway"],
  });
  assert.strictEqual(result.version, 2);

  const live = await rewardDoc(rewardId);
  assert.strictEqual(live?.version, 2);
  assert.deepStrictEqual(live?.eligibleChannels, ["takeaway"]);

  const v2 = await versionDoc(rewardId, 2);
  assert.deepStrictEqual(v2?.eligibleChannels, ["takeaway"]);

  const v1After = await versionDoc(rewardId, 1);
  assert.deepStrictEqual(
    v1After,
    v1Before,
    "V1's own eligibleChannels (and every other field) must remain unchanged after V2 narrows the channel scope",
  );
});

test("createLoyaltyReward: empty eligibleChannels is rejected, no doc created", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);
  await assert.rejects(() =>
    createLoyaltyReward(db(), { ...validInput(orgId, rewardId, [productId]), eligibleChannels: [] }),
  );
  assert.strictEqual(await rewardDoc(rewardId), undefined);
});

test("createLoyaltyReward: an unsupported channel value is rejected, no doc created", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);
  await assert.rejects(() =>
    createLoyaltyReward(db(), {
      ...validInput(orgId, rewardId, [productId]),
      eligibleChannels: ["takeaway", "drone"],
    }),
  );
  assert.strictEqual(await rewardDoc(rewardId), undefined);
});

test("createLoyaltyReward: duplicate channels in the input are normalized deterministically, never rejected", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);
  const result = await createLoyaltyReward(db(), {
    ...validInput(orgId, rewardId, [productId]),
    eligibleChannels: ["takeaway", "takeaway", "delivery"],
  });
  assert.strictEqual(result.created, true);
  const live = await rewardDoc(rewardId);
  assert.deepStrictEqual(live?.eligibleChannels, ["takeaway", "delivery"]);
});

test("createLoyaltyReward: missing eligibleChannels entirely is rejected, no doc created", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);
  const { eligibleChannels: _omit, ...withoutChannels } = validInput(orgId, rewardId, [productId]);
  await assert.rejects(() =>
    createLoyaltyReward(db(), withoutChannels as unknown as Parameters<typeof createLoyaltyReward>[1]),
  );
  assert.strictEqual(await rewardDoc(rewardId), undefined);
});

test("createLoyaltyReward: idempotent create — eligibleChannels present in both the live doc and the version doc", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);
  await createLoyaltyReward(db(), {
    ...validInput(orgId, rewardId, [productId]),
    eligibleChannels: ["delivery"],
  });
  const live = await rewardDoc(rewardId);
  const v1 = await versionDoc(rewardId, 1);
  assert.deepStrictEqual(live?.eligibleChannels, ["delivery"]);
  assert.deepStrictEqual(v1?.eligibleChannels, ["delivery"]);
});

test("updateLoyaltyRewardByCreatingNextVersion: a nonexistent reward is rejected", async () => {
  const orgId = nextId("org");
  await seedOrg(orgId);
  await assert.rejects(() =>
    updateLoyaltyRewardByCreatingNextVersion(db(), orgId, "does-not-exist", { boncukCost: 100 }),
  );
});

// =========================================================================
// C. setLoyaltyRewardActive / archiveLoyaltyReward — no new version
// =========================================================================

test("setLoyaltyRewardActive: toggles active on the live doc WITHOUT creating a new version", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);
  await createLoyaltyReward(db(), validInput(orgId, rewardId, [productId]));

  await setLoyaltyRewardActive(db(), orgId, rewardId, false);
  let live = await rewardDoc(rewardId);
  assert.strictEqual(live?.active, false);
  assert.strictEqual(live?.version, 1, "deactivating must never bump the version");

  await setLoyaltyRewardActive(db(), orgId, rewardId, true);
  live = await rewardDoc(rewardId);
  assert.strictEqual(live?.active, true);
  assert.strictEqual(live?.version, 1, "reactivating must never bump the version");

  const versionsSnap = await db()
    .collection(LOYALTY_REWARD_CATALOG_VERSIONS_COLLECTION)
    .where("rewardId", "==", rewardId)
    .get();
  assert.strictEqual(versionsSnap.size, 1, "no new version doc from either toggle");
});

test("archiveLoyaltyReward: sets archived:true, active:false; the reward can never be reactivated afterward", async () => {
  const orgId = nextId("org");
  const rewardId = nextId("reward");
  const productId = nextId("prod");
  await seedOrg(orgId);
  await seedProduct(productId, orgId);
  await createLoyaltyReward(db(), validInput(orgId, rewardId, [productId]));

  await archiveLoyaltyReward(db(), orgId, rewardId);
  const live = await rewardDoc(rewardId);
  assert.strictEqual(live?.archived, true);
  assert.strictEqual(live?.active, false);
  assert.strictEqual(live?.version, 1, "archiving must never bump the version");

  await assert.rejects(() => setLoyaltyRewardActive(db(), orgId, rewardId, true));
});
