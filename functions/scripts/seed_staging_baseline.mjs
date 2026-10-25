// Staging end-to-end test-data seed — the REAL-project counterpart to
// `seed_dev_tenant.mjs`/`seed_dev_catalog.mjs`/`seed_dev_table_qr.mjs`,
// which all explicitly refuse to run against anything but the local
// emulator. Those scripts are the wrong tool here on purpose: `seed_dev_tenant
// .mjs` mints its platformOwner token for a throwaway ANONYMOUS user via the
// Auth emulator's REST API — something that must never happen against a
// real project. This script instead mints a real custom token (via the
// Admin SDK) for an ALREADY-bootstrapped real platformOwner uid
// (`bootstrap_platform_owner.mjs` must have already run for the target
// project) and exchanges it for a real ID token through the real Identity
// Toolkit REST API, then calls the real deployed `provisionOrganization`/
// `provisionRestaurant`/`provisionBranch` callables with it — same
// validation/idempotency path a real admin's own sign-in would go through,
// never a direct Firestore write for that chain.
//
// Menu (`menuProducts`/`bowlIngredients`/`channelPricingPolicies`) and table/
// QR (`restaurantTables`/`tableQrCodes`) data has no `provision*` callable at
// all in this codebase (confirmed in `seed_dev_catalog.mjs`/
// `seed_dev_table_qr.mjs`'s own doc comments — there is no authorization
// logic to bypass for these collections), so this script writes those
// directly via the Admin SDK, exactly like its emulator-only counterparts —
// only the tenant-chain step goes through real callables.
//
// SAFETY: requires GCLOUD_PROJECT, GOOGLE_APPLICATION_CREDENTIALS (a real
// service account key), WEB_API_KEY (the target project's Web FirebaseOptions
// apiKey — needed for the Identity Toolkit custom-token exchange; Android/iOS
// keys may carry app-restrictions that reject a plain server-side REST call),
// and a real, already-bootstrapped platformOwner uid as the one CLI argument.
// Never hardcodes a project id or uid. Refuses outright if GCLOUD_PROJECT
// looks like an emulator demo project, inverting every `seed_dev_*.mjs`
// script's own emulator-only guard — this script's entire purpose is a real
// project, so accidentally running it against the emulator would silently
// seed the wrong place.
//
// Safe to re-run — every write below is either a provision* callable
// (already idempotent by design) or a fixed-id `.set()` upsert.
//
// Usage:
//   cd functions
//   GCLOUD_PROJECT=<real-project-id> \
//   GOOGLE_APPLICATION_CREDENTIALS=<path-to-service-account-key.json> \
//   WEB_API_KEY=<project's web FirebaseOptions apiKey> \
//   node scripts/seed_staging_baseline.mjs <platformOwnerUid>

import admin from "firebase-admin";

function usageAndExit(message) {
  if (message) console.error(`[seed_staging_baseline] ${message}`);
  console.error(
    "[seed_staging_baseline] usage: GCLOUD_PROJECT=... GOOGLE_APPLICATION_CREDENTIALS=... " +
      "WEB_API_KEY=... node scripts/seed_staging_baseline.mjs <platformOwnerUid>",
  );
  process.exit(1);
}

const projectId = process.env.GCLOUD_PROJECT;
if (!projectId) usageAndExit("GCLOUD_PROJECT must be set to the real target project id.");
if (projectId.startsWith("demo-")) {
  usageAndExit(
    `GCLOUD_PROJECT ("${projectId}") looks like an emulator demo project — this script is ` +
      "only for a real project. Use seed_dev_tenant.mjs/seed_dev_catalog.mjs/" +
      "seed_dev_table_qr.mjs under firebase emulators:exec instead.",
  );
}
const webApiKey = process.env.WEB_API_KEY;
if (!webApiKey) usageAndExit("WEB_API_KEY must be set to the project's Web FirebaseOptions apiKey.");
const platformOwnerUid = process.argv[2];
if (!platformOwnerUid) usageAndExit("a real, already-bootstrapped platformOwner uid is required.");

const ORGANIZATION_ID = "org-1";
const RESTAURANT_ID = "restaurant-1";
const BRANCH_ID = "branch-1";
const FUNCTIONS_BASE = `https://us-central1-${projectId}.cloudfunctions.net`;

const app = admin.initializeApp({ projectId });
const db = admin.firestore();

async function callCallable(name, data, idToken) {
  const response = await fetch(`${FUNCTIONS_BASE}/${name}`, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${idToken}` },
    body: JSON.stringify({ data }),
  });
  const body = await response.json();
  if (body.error) {
    throw new Error(`${name} failed: ${body.error.status} — ${body.error.message}`);
  }
  return body.result;
}

async function mintRealIdToken(uid) {
  const customToken = await admin.auth().createCustomToken(uid);
  const response = await fetch(
    `https://identitytoolkit.googleapis.com/v1/accounts:signInWithCustomToken?key=${webApiKey}`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ token: customToken, returnSecureToken: true }),
    },
  );
  const body = await response.json();
  if (!body.idToken) {
    throw new Error(`Failed to exchange custom token for an ID token: ${JSON.stringify(body)}`);
  }
  return body.idToken;
}

async function seedTenantChain(idToken) {
  const organization = await callCallable(
    "provisionOrganization",
    { organizationId: ORGANIZATION_ID, name: "Abaküs" },
    idToken,
  );
  console.log(`[seed_staging_baseline] organizations/${ORGANIZATION_ID}: ${organization.created ? "created" : "already existed"}`);

  const restaurant = await callCallable(
    "provisionRestaurant",
    { organizationId: ORGANIZATION_ID, restaurantId: RESTAURANT_ID, name: "Abaküs Bowl" },
    idToken,
  );
  console.log(`[seed_staging_baseline] restaurants/${RESTAURANT_ID}: ${restaurant.created ? "created" : "already existed"}`);

  const branch = await callCallable(
    "provisionBranch",
    {
      organizationId: ORGANIZATION_ID,
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      name: "Merkez Şube",
      supportedOrderChannelIds: ["dineInQr", "dineInStaff", "delivery", "takeaway"],
    },
    idToken,
  );
  console.log(`[seed_staging_baseline] branches/${BRANCH_ID}: ${branch.created ? "created" : "already existed"}`);
}

async function seedMenu() {
  await db.collection("channelPricingPolicies").doc(RESTAURANT_ID).set({
    channelDefaultAdjustments: { takeaway: 2000 },
    categoryOverrides: { takeaway: { cat_icecekler: 0 } },
  });

  const products = [
    {
      id: "prod_mexifit_bowl",
      categoryId: "cat_bowl",
      name: "Mexifit Bowl",
      basePriceMinorUnits: 43000,
      isAvailable: true,
      modifierGroups: [
        {
          id: "protein_choice",
          name: "Protein",
          selectionType: "single",
          isRequired: false,
          minSelections: 0,
          maxSelections: 1,
          options: [
            { id: "chicken", name: "Izgara Tavuk", extraPriceMinorUnits: 0, isAvailable: true },
            { id: "extra_chicken", name: "Ekstra Tavuk", extraPriceMinorUnits: 3000, isAvailable: true },
          ],
        },
      ],
      channelPriceOverrides: {},
    },
    {
      id: "prod_ayran",
      categoryId: "cat_icecekler",
      name: "Ayran",
      basePriceMinorUnits: 4000,
      isAvailable: true,
      modifierGroups: [],
      channelPriceOverrides: {},
    },
    {
      id: "prod_tavuk_salata",
      categoryId: "cat_salata",
      name: "Izgara Tavuklu Salata",
      basePriceMinorUnits: 24000,
      isAvailable: true,
      modifierGroups: [],
      channelPriceOverrides: {},
    },
  ];
  for (const product of products) {
    await db.collection("menuProducts").doc(product.id).set({
      organizationId: ORGANIZATION_ID,
      restaurantId: RESTAURANT_ID,
      categoryId: product.categoryId,
      name: product.name,
      basePriceMinorUnits: product.basePriceMinorUnits,
      isAvailable: product.isAvailable,
      modifierGroups: product.modifierGroups,
      channelPriceOverrides: product.channelPriceOverrides,
    });
  }
  console.log(`[seed_staging_baseline] menuProducts: ${products.length} products provisioned.`);

  const ingredients = [
    { id: "bowl_ing_chicken", categoryId: "protein", name: "Izgara Tavuk", priceMinorUnits: 15000 },
    { id: "bowl_ing_rice", categoryId: "carbs", name: "Pirinç Pilavı", priceMinorUnits: 5000 },
    { id: "bowl_ing_yogurt_sauce", categoryId: "sauces", name: "Yoğurt Sos", priceMinorUnits: 2000 },
  ];
  for (const ingredient of ingredients) {
    await db.collection("bowlIngredients").doc(ingredient.id).set({
      organizationId: ORGANIZATION_ID,
      restaurantId: RESTAURANT_ID,
      categoryId: ingredient.categoryId,
      name: ingredient.name,
      priceMinorUnits: ingredient.priceMinorUnits,
      isAvailable: true,
    });
  }
  console.log(`[seed_staging_baseline] bowlIngredients: ${ingredients.length} ingredients provisioned.`);
}

async function seedTables() {
  const now = new Date();
  const tables = [
    { id: "table-1", displayName: "Masa 1", areaName: "Salon", capacity: 2, sortOrder: 1, token: "STAGING-ABAKUS-T1" },
    { id: "table-2", displayName: "Masa 2", areaName: "Salon", capacity: 4, sortOrder: 2, token: "STAGING-ABAKUS-T2" },
    { id: "table-3", displayName: "Masa 3 (Teras)", areaName: "Teras", capacity: 6, sortOrder: 3, token: "STAGING-ABAKUS-T3" },
  ];

  for (const table of tables) {
    await db.collection("restaurantTables").doc(table.id).set({
      organizationId: ORGANIZATION_ID,
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      branchDisplayName: "Merkez Şube",
      floorPlanId: "staging-floor-plan-1",
      displayName: table.displayName,
      areaName: table.areaName,
      reservationAreaId: null,
      capacity: table.capacity,
      status: "available",
      sortOrder: table.sortOrder,
      isActive: true,
      createdAt: now,
      updatedAt: now,
      revision: 1,
    });

    await db.collection("tableQrCodes").doc(`staging-table-qr-${table.id}`).set({
      tableId: table.id,
      branchId: BRANCH_ID,
      opaqueToken: table.token,
      status: "active",
      createdAt: now,
      updatedAt: now,
      revision: 1,
    });
    console.log(`[seed_staging_baseline] restaurantTables/${table.id} + its QR token (${table.token}): provisioned.`);
  }
}

async function main() {
  console.log(`[seed_staging_baseline] target project: "${projectId}"`);
  console.log(`[seed_staging_baseline] minting a real ID token for platformOwner uid "${platformOwnerUid}"...`);
  const firstToken = await mintRealIdToken(platformOwnerUid);

  // bootstrap_platform_owner.mjs only writes platformMembers/{uid} in
  // Firestore — it never calls setCustomUserClaims itself (by design, one
  // tier up from staffMembership.ts's own resyncClaimsForUid split). The
  // uid's Auth custom claim is still empty until syncOwnPlatformClaims runs
  // at least once, so a token minted before that call never carries
  // platformRole. Call it now with the first token (uid alone is enough —
  // it doesn't need the claim to already be set), then mint a second,
  // fresh token that actually carries the newly-synced claim.
  console.log("[seed_staging_baseline] syncing platform claims for the uid...");
  await callCallable("syncOwnPlatformClaims", {}, firstToken);
  const idToken = await mintRealIdToken(platformOwnerUid);

  await seedTenantChain(idToken);
  await seedMenu();
  await seedTables();

  console.log("[seed_staging_baseline] done.");
  await app.delete();
}

main().catch((error) => {
  console.error("[seed_staging_baseline] failed:", error);
  process.exitCode = 1;
});
