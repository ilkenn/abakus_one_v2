import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import {
  createCampaign,
  updateCampaignByCreatingNextVersion,
  setCampaignActive,
  archiveCampaign,
  duplicateCampaign,
  type CreateCampaignInput,
} from "../campaignAdminService";
import { CAMPAIGNS_COLLECTION, CAMPAIGN_VERSIONS_COLLECTION, campaignVersionDocId } from "../campaignEngine";

/**
 * Emulator-backed tests for `campaignAdminService.ts` — Server-
 * Authoritative Campaign Engine P8-B (2026-08-25). Plain trusted functions
 * (not `onCall` callables), so this file calls them directly against a real
 * Admin-SDK-connected `Firestore` instance, mirroring
 * `loyaltyRewardCatalogAdminService.test.ts`'s own exact shape.
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

async function seedProduct(productId: string, organizationId: string, categoryId = "cat_test") {
  await db().collection("menuProducts").doc(productId).set({
    organizationId,
    restaurantId: "restaurant-x",
    categoryId,
    name: "Test Product",
    basePriceMinorUnits: 10000,
    isAvailable: true,
    modifierGroups: [],
    channelPriceOverrides: {},
  });
}

async function campaignDoc(campaignId: string) {
  return (await db().collection(CAMPAIGNS_COLLECTION).doc(campaignId).get()).data();
}

async function versionDoc(campaignId: string, version: number) {
  return (await db().collection(CAMPAIGN_VERSIONS_COLLECTION).doc(campaignVersionDocId(campaignId, version)).get()).data();
}

function orderWidePercentInput(
  organizationId: string,
  campaignId: string,
  overrides: Partial<CreateCampaignInput> = {},
): CreateCampaignInput {
  return {
    organizationId,
    campaignId,
    title: "Test Campaign",
    description: "Bir test kampanyası.",
    campaignType: "percentageDiscount",
    rule: { mechanic: "percentage", percentBasisPoints: 1500, scope: { kind: "order" } },
    eligibleChannels: ["dineIn", "takeaway"],
    schedule: { mode: "oneTime", startAt: null, endAt: null },
    sortOrder: 0,
    ...overrides,
  };
}

// =========================================================================
// A. createCampaign
// =========================================================================

test("createCampaign: creates a live doc (version 1, active, not archived) and a matching version-1 snapshot", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  await seedOrg(organizationId);

  const result = await createCampaign(db(), orderWidePercentInput(organizationId, campaignId));
  assert.deepStrictEqual(result, { campaignId, version: 1, created: true });

  const live = await campaignDoc(campaignId);
  assert.strictEqual(live?.active, true);
  assert.strictEqual(live?.archived, false);
  assert.strictEqual(live?.version, 1);

  const version = await versionDoc(campaignId, 1);
  assert.strictEqual(version?.version, 1);
  assert.deepStrictEqual(version?.rule, { mechanic: "percentage", percentBasisPoints: 1500, scope: { kind: "order" } });
});

test("createCampaign: idempotent — a repeat call with the same campaignId is a safe no-op, created: false", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  await seedOrg(organizationId);

  const first = await createCampaign(db(), orderWidePercentInput(organizationId, campaignId));
  const second = await createCampaign(
    db(),
    orderWidePercentInput(organizationId, campaignId, { title: "A Completely Different Title" }),
  );
  assert.strictEqual(first.created, true);
  assert.deepStrictEqual(second, { campaignId, version: 1, created: false });
  // The second call's differing title never overwrote the live doc.
  const live = await campaignDoc(campaignId);
  assert.strictEqual(live?.title, "Test Campaign");
});

test("createCampaign: rejects a campaignType/rule mismatch", async () => {
  const organizationId = nextId("org");
  await seedOrg(organizationId);
  await assert.rejects(
    createCampaign(
      db(),
      orderWidePercentInput(organizationId, nextId("camp"), {
        campaignType: "categoryDiscount",
        rule: { mechanic: "percentage", percentBasisPoints: 1000, scope: { kind: "order" } },
      }),
    ),
    RangeError,
  );
});

test("createCampaign: rejects when the organization does not exist", async () => {
  await assert.rejects(
    createCampaign(db(), orderWidePercentInput("nonexistent-org", nextId("camp"))),
    (error: unknown) => {
      assert.ok(error instanceof HttpsError);
      assert.strictEqual(error.code, "failed-precondition");
      return true;
    },
  );
});

test("createCampaign: rejects when the organization is inactive", async () => {
  const organizationId = nextId("org");
  await seedOrg(organizationId, false);
  await assert.rejects(createCampaign(db(), orderWidePercentInput(organizationId, nextId("camp"))));
});

test("createCampaign: productDiscount rejects a product id that does not exist in canonical menuProducts — never trusts a client-asserted product", async () => {
  const organizationId = nextId("org");
  await seedOrg(organizationId);
  await assert.rejects(
    createCampaign(
      db(),
      orderWidePercentInput(organizationId, nextId("camp"), {
        campaignType: "productDiscount",
        rule: {
          mechanic: "percentage",
          percentBasisPoints: 2000,
          scope: { kind: "product", productId: "does-not-exist" },
        },
      }),
    ),
    (error: unknown) => {
      assert.ok(error instanceof HttpsError);
      assert.strictEqual(error.code, "failed-precondition");
      return true;
    },
  );
});

test("createCampaign: productDiscount rejects a real product belonging to a DIFFERENT organization — cross-tenant fails closed", async () => {
  const organizationId = nextId("org");
  const otherOrganizationId = nextId("org");
  await seedOrg(organizationId);
  await seedOrg(otherOrganizationId);
  const productId = nextId("prod");
  await seedProduct(productId, otherOrganizationId);

  await assert.rejects(
    createCampaign(
      db(),
      orderWidePercentInput(organizationId, nextId("camp"), {
        campaignType: "productDiscount",
        rule: { mechanic: "percentage", percentBasisPoints: 2000, scope: { kind: "product", productId } },
      }),
    ),
  );
});

test("createCampaign: productDiscount accepts a real, same-organization product", async () => {
  const organizationId = nextId("org");
  await seedOrg(organizationId);
  const productId = nextId("prod");
  await seedProduct(productId, organizationId);

  const campaignId = nextId("camp");
  const result = await createCampaign(
    db(),
    orderWidePercentInput(organizationId, campaignId, {
      campaignType: "productDiscount",
      rule: { mechanic: "percentage", percentBasisPoints: 2000, scope: { kind: "product", productId } },
    }),
  );
  assert.strictEqual(result.created, true);
});

test("createCampaign: categoryDiscount rejects a category id with no real menuProducts member — a Bowl Builder-shaped fake category id can never pass", async () => {
  const organizationId = nextId("org");
  await seedOrg(organizationId);
  await assert.rejects(
    createCampaign(
      db(),
      orderWidePercentInput(organizationId, nextId("camp"), {
        campaignType: "categoryDiscount",
        rule: {
          mechanic: "fixedAmount",
          amountMinorUnits: 5000,
          scope: { kind: "category", categoryId: "custom_bowl_category" },
        },
      }),
    ),
  );
});

test("createCampaign: categoryDiscount accepts a category with at least one real product in it", async () => {
  const organizationId = nextId("org");
  await seedOrg(organizationId);
  const productId = nextId("prod");
  await seedProduct(productId, organizationId, "pasta");

  const campaignId = nextId("camp");
  const result = await createCampaign(
    db(),
    orderWidePercentInput(organizationId, campaignId, {
      campaignType: "categoryDiscount",
      rule: { mechanic: "fixedAmount", amountMinorUnits: 5000, scope: { kind: "category", categoryId: "pasta" } },
    }),
  );
  assert.strictEqual(result.created, true);
});

// =========================================================================
// B. updateCampaignByCreatingNextVersion — immutable versioning
// =========================================================================

test("updateCampaignByCreatingNextVersion: creates version 2, never mutates version 1's own snapshot", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  await seedOrg(organizationId);
  await createCampaign(db(), orderWidePercentInput(organizationId, campaignId));

  const result = await updateCampaignByCreatingNextVersion(db(), organizationId, campaignId, {
    rule: { mechanic: "percentage", percentBasisPoints: 2500, scope: { kind: "order" } },
  });
  assert.strictEqual(result.version, 2);

  const v1 = await versionDoc(campaignId, 1);
  const v2 = await versionDoc(campaignId, 2);
  assert.deepStrictEqual(v1?.rule, { mechanic: "percentage", percentBasisPoints: 1500, scope: { kind: "order" } });
  assert.deepStrictEqual(v2?.rule, { mechanic: "percentage", percentBasisPoints: 2500, scope: { kind: "order" } });

  const live = await campaignDoc(campaignId);
  assert.strictEqual(live?.version, 2);
});

test("updateCampaignByCreatingNextVersion: an omitted field carries over unchanged from the current live definition", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  await seedOrg(organizationId);
  await createCampaign(db(), orderWidePercentInput(organizationId, campaignId, { title: "Original Title" }));

  await updateCampaignByCreatingNextVersion(db(), organizationId, campaignId, {
    rule: { mechanic: "percentage", percentBasisPoints: 3000, scope: { kind: "order" } },
  });

  const live = await campaignDoc(campaignId);
  assert.strictEqual(live?.title, "Original Title");
});

test("updateCampaignByCreatingNextVersion: rejects an update on a nonexistent campaign", async () => {
  const organizationId = nextId("org");
  await seedOrg(organizationId);
  await assert.rejects(
    updateCampaignByCreatingNextVersion(db(), organizationId, "does-not-exist", {}),
    (error: unknown) => {
      assert.ok(error instanceof HttpsError);
      assert.strictEqual(error.code, "not-found");
      return true;
    },
  );
});

test("updateCampaignByCreatingNextVersion: rejects cross-tenant update (right campaignId, wrong organizationId)", async () => {
  const organizationId = nextId("org");
  const otherOrganizationId = nextId("org");
  await seedOrg(organizationId);
  await seedOrg(otherOrganizationId);
  const campaignId = nextId("camp");
  await createCampaign(db(), orderWidePercentInput(organizationId, campaignId));

  await assert.rejects(updateCampaignByCreatingNextVersion(db(), otherOrganizationId, campaignId, {}));
});

// =========================================================================
// C. setCampaignActive / archiveCampaign — never a new version, never destructive
// =========================================================================

test("setCampaignActive: toggling active does NOT bump version or create a new version snapshot", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  await seedOrg(organizationId);
  await createCampaign(db(), orderWidePercentInput(organizationId, campaignId));

  await setCampaignActive(db(), organizationId, campaignId, false);
  const live = await campaignDoc(campaignId);
  assert.strictEqual(live?.active, false);
  assert.strictEqual(live?.version, 1);
  const v2 = await versionDoc(campaignId, 2);
  assert.strictEqual(v2, undefined);
});

test("archiveCampaign: forces active:false, archived:true, never a new version — the doc and its versions remain permanently stored", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  await seedOrg(organizationId);
  await createCampaign(db(), orderWidePercentInput(organizationId, campaignId));

  await archiveCampaign(db(), organizationId, campaignId);
  const live = await campaignDoc(campaignId);
  assert.strictEqual(live?.active, false);
  assert.strictEqual(live?.archived, true);
  assert.strictEqual(live?.version, 1);
  // The live document itself still exists — never deleted.
  assert.notStrictEqual(live, undefined);
});

test("setCampaignActive: an archived campaign cannot be reactivated through this operation — archiving is terminal", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  await seedOrg(organizationId);
  await createCampaign(db(), orderWidePercentInput(organizationId, campaignId));
  await archiveCampaign(db(), organizationId, campaignId);

  await assert.rejects(
    setCampaignActive(db(), organizationId, campaignId, true),
    (error: unknown) => {
      assert.ok(error instanceof HttpsError);
      assert.strictEqual(error.code, "failed-precondition");
      return true;
    },
  );
});

// =========================================================================
// D. duplicateCampaign
// =========================================================================

test("duplicateCampaign: copies the full rule-defining definition into a new campaignId as version 1, deliberately inactive", async () => {
  const organizationId = nextId("org");
  const sourceId = nextId("camp");
  const newId = nextId("camp");
  await seedOrg(organizationId);
  await createCampaign(db(), orderWidePercentInput(organizationId, sourceId, { title: "Source Campaign" }));

  const result = await duplicateCampaign(db(), organizationId, sourceId, newId);
  assert.deepStrictEqual(result, { campaignId: newId, version: 1 });

  const duplicated = await campaignDoc(newId);
  assert.strictEqual(duplicated?.title, "Source Campaign");
  assert.strictEqual(duplicated?.active, false);
  assert.strictEqual(duplicated?.archived, false);
  assert.strictEqual(duplicated?.version, 1);

  // The source campaign itself is completely unaffected.
  const source = await campaignDoc(sourceId);
  assert.strictEqual(source?.active, true);
});

test("duplicateCampaign: rejects duplicating into an already-existing campaignId", async () => {
  const organizationId = nextId("org");
  const sourceId = nextId("camp");
  const existingId = nextId("camp");
  await seedOrg(organizationId);
  await createCampaign(db(), orderWidePercentInput(organizationId, sourceId));
  await createCampaign(db(), orderWidePercentInput(organizationId, existingId));

  await assert.rejects(
    duplicateCampaign(db(), organizationId, sourceId, existingId),
    (error: unknown) => {
      assert.ok(error instanceof HttpsError);
      assert.strictEqual(error.code, "already-exists");
      return true;
    },
  );
});

test("duplicateCampaign: rejects duplicating a nonexistent source campaign", async () => {
  const organizationId = nextId("org");
  await seedOrg(organizationId);
  await assert.rejects(duplicateCampaign(db(), organizationId, "does-not-exist", nextId("camp")));
});
