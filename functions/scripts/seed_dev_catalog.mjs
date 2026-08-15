// Faz D.3 — reusable dev/emulator canonical menu catalog seed.
//
// **SUPERSEDED as of Faz D.3.1/D.3.1.1 — not part of `seed:dev-all` or
// `migrate:catalog`'s chain, kept only for manual/historical use.** The
// real, full catalog migration (`migrate_canonical_catalog.mjs`, sourced
// from the real Dart `AbakusMenuCatalog`/`LocalBowlBuilderCatalogRepository`)
// is a strict superset of what this script seeds — every id below is
// overwritten by that migration if both are ever run against the same
// restaurant. Its `channelPricingPolicies` write is likewise superseded:
// that document is now written by `migrateCanonicalCatalog` itself,
// sourced from the real Dart `InMemoryChannelPricingPolicyRepository` (Faz
// D.3.1.1) — keeping this script's own independent, hand-typed copy of
// the same +20/+0 values running alongside it would be exactly the "two
// independent pricing seed implementations" that phase explicitly closed.
// Left in place, unmodified otherwise, only because deleting a file is a
// decision for the human, not taken unilaterally here (`CLAUDE.md` §15) —
// do not add a fresh dependency on it.
//
// Writes a REPRESENTATIVE subset of Firestore-canonical
// `menuProducts`/`bowlIngredients`/`channelPricingPolicies` documents,
// bound to this app's real canonical tenant chain (org-1 -> restaurant-1
// -> branch-1 — requires `npm run seed:dev-tenant` to have run first).
//
// **Scope decision, stated explicitly**: this seeds enough products/
// ingredients to exercise every pricing rule (a drink at +0, a normal
// product at +20, a fixed-adjustment override, an explicit-price
// override, a product with modifier groups, a few bowl ingredients) —
// NOT the full ~84-product real menu (`AbakusMenuCatalog`). A full
// content migration into Firestore is separate, future work.
//
// Uses the Admin SDK to write directly — the intended path for these
// collections, exactly like `seed_dev_takeaway_qr.mjs`: no
// `provisionMenuProduct`-style callable exists (or was asked for) this
// phase, so there is no authorization/validation logic for this script to
// bypass.
//
// Safe to re-run any time — every document uses a fixed, deterministic
// id, so re-running upserts rather than duplicates.
//
// SAFETY: refuses to run unless FIRESTORE_EMULATOR_HOST is set. Run via:
//
//   cd functions
//   firebase emulators:exec --only firestore,functions,auth \
//     "node scripts/seed_dev_tenant.mjs && node scripts/seed_dev_catalog.mjs"

import admin from "firebase-admin";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    "[seed_dev_catalog] FIRESTORE_EMULATOR_HOST is not set — refusing to " +
      "run against anything but the local emulator suite. Run via " +
      '`firebase emulators:exec --only firestore,functions,auth ' +
      '"node scripts/seed_dev_tenant.mjs && node scripts/seed_dev_catalog.mjs"`.',
  );
  process.exit(1);
}

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-abakus-one-emulator";
const ORGANIZATION_ID = "org-1";
const RESTAURANT_ID = "restaurant-1";

const app = admin.initializeApp({ projectId: PROJECT_ID });

async function main() {
  const db = admin.firestore();

  const restaurantDoc = await db.collection("restaurants").doc(RESTAURANT_ID).get();
  if (!restaurantDoc.exists) {
    console.error(
      `[seed_dev_catalog] restaurants/${RESTAURANT_ID} does not exist — run ` +
        "`npm run seed:dev-tenant` first.",
    );
    process.exit(1);
  }

  // --- Channel pricing policy (Faz A rule, mirrored exactly: every
  // product +20 TL on takeaway by default, İçecekler exempted at +0) ---
  await db.collection("channelPricingPolicies").doc(RESTAURANT_ID).set({
    channelDefaultAdjustments: { takeaway: 2000 },
    categoryOverrides: { takeaway: { cat_icecekler: 0 } },
  });
  console.log("[seed_dev_catalog] channelPricingPolicies/restaurant-1: provisioned.");

  // --- Menu products (representative subset of the real AbakusMenuCatalog) ---
  const products = [
    {
      id: "prod_mexifit_bowl",
      categoryId: "cat_bowl",
      name: "Mexifit Bowl",
      basePriceMinorUnits: 43000, // 430 TL — real menu price
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
      basePriceMinorUnits: 4000, // 40 TL
      isAvailable: true,
      modifierGroups: [],
      channelPriceOverrides: {},
    },
    {
      id: "prod_fixed_override_example",
      categoryId: "cat_atistirmalik",
      name: "Kampanyalı Atıştırmalık",
      basePriceMinorUnits: 15000,
      isAvailable: true,
      modifierGroups: [],
      // Fixed +10 TL on takeaway instead of the +20 TL category default —
      // proves the product-level override precedence works against real
      // seeded data, not just unit-test fixtures.
      channelPriceOverrides: { takeaway: { type: "fixedAdjustment", adjustmentMinorUnits: 1000 } },
    },
    {
      id: "prod_explicit_override_example",
      categoryId: "cat_hamburger",
      name: "Gel Al Özel Burger",
      basePriceMinorUnits: 25000,
      isAvailable: true,
      modifierGroups: [],
      // Always 599 TL on takeaway, entirely independent of basePrice.
      channelPriceOverrides: { takeaway: { type: "explicitPrice", priceMinorUnits: 59900 } },
    },
    {
      id: "prod_inactive_example",
      categoryId: "cat_salata",
      name: "Mevsimlik Salata (Stokta Yok)",
      basePriceMinorUnits: 18000,
      isAvailable: false,
      modifierGroups: [],
      channelPriceOverrides: {},
    },
  ];

  for (const product of products) {
    await db
      .collection("menuProducts")
      .doc(product.id)
      .set({
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
  console.log(`[seed_dev_catalog] menuProducts: ${products.length} products provisioned.`);

  // --- Bowl Builder ingredients (representative subset) ---
  const ingredients = [
    { id: "bowl_ing_chicken", categoryId: "protein", name: "Izgara Tavuk", priceMinorUnits: 15000 },
    { id: "bowl_ing_falafel", categoryId: "protein", name: "Falafel", priceMinorUnits: 12000 },
    { id: "bowl_ing_rice", categoryId: "carbs", name: "Pirinç Pilavı", priceMinorUnits: 5000 },
    { id: "bowl_ing_yogurt_sauce", categoryId: "sauces", name: "Yoğurt Sos", priceMinorUnits: 2000 },
    { id: "bowl_ing_inactive", categoryId: "sauces", name: "Mevsimlik Sos (Stokta Yok)", priceMinorUnits: 2000, isAvailable: false },
  ];
  for (const ingredient of ingredients) {
    await db
      .collection("bowlIngredients")
      .doc(ingredient.id)
      .set({
        organizationId: ORGANIZATION_ID,
        restaurantId: RESTAURANT_ID,
        categoryId: ingredient.categoryId,
        name: ingredient.name,
        priceMinorUnits: ingredient.priceMinorUnits,
        isAvailable: ingredient.isAvailable !== false,
      });
  }
  console.log(`[seed_dev_catalog] bowlIngredients: ${ingredients.length} ingredients provisioned.`);

  await app.delete();
}

main().catch((error) => {
  console.error("[seed_dev_catalog] failed:", error);
  process.exitCode = 1;
});
