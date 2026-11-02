// 2026-10-28 — real-project counterpart to `migrate_canonical_catalog.mjs`.
//
// That script hard-refuses to run against anything but the local emulator
// (by design — see its own SAFETY comment). For the Cumartesi launch, the
// 2026-10-28 PDF menu refresh (`AbakusMenuCatalog`, now 171 products across
// 16 categories — see `docs/feature_status.md`'s dated entry) needs to
// reach the real `abakus-one-staging` project, not just the emulator. This
// script calls the exact same, already-tested `migrateCanonicalCatalog`
// (`src/catalogMigration.ts` — the same function
// `functions/src/test/catalogMigration.test.ts` exercises) against a real
// project's Firestore instead, so there is no second, independently-
// drifting write path.
//
// SAFETY: requires an explicit `--project` matching an allow-listed real
// project id, and real Admin SDK credentials via
// `GOOGLE_APPLICATION_CREDENTIALS` (never hardcoded, never committed).
// Idempotent — `migrateCanonicalCatalog` is `.set()`-based upsert on
// deterministic ids, safe to re-run any time the Dart catalog changes.
//
// Usage:
//   dart run tool/export_menu_catalog.dart
//   cd functions && npm run build
//   GOOGLE_APPLICATION_CREDENTIALS=/path/to/staging-service-account.json \
//     node scripts/migrate_canonical_catalog_to_project.mjs --project abakus-one-staging

import admin from "firebase-admin";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";
import { createRequire } from "module";

const ALLOWED_PROJECT_IDS = new Set(["abakus-one-staging", "abakusone"]);

const projectArgIndex = process.argv.indexOf("--project");
const PROJECT_ID = projectArgIndex !== -1 ? process.argv[projectArgIndex + 1] : null;

if (!PROJECT_ID || !ALLOWED_PROJECT_IDS.has(PROJECT_ID)) {
  console.error(
    "[migrate_canonical_catalog_to_project] --project is required and must be one of: " +
      `${[...ALLOWED_PROJECT_IDS].join(", ")}. Got: ${PROJECT_ID ?? "(none)"}.`,
  );
  process.exit(1);
}

if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) {
  console.error(
    "[migrate_canonical_catalog_to_project] GOOGLE_APPLICATION_CREDENTIALS is not set — " +
      "point it at a real service-account key for this project before running.",
  );
  process.exit(1);
}

const ORGANIZATION_ID = "org-1";
const RESTAURANT_ID = "restaurant-1";

const __dirname = dirname(fileURLToPath(import.meta.url));
const EXPORT_PATH = join(__dirname, "data", "menu_catalog_export.json");

const require = createRequire(import.meta.url);
const { migrateCanonicalCatalog } = require("../lib/catalogMigration.js");

const app = admin.initializeApp({ projectId: PROJECT_ID });

async function main() {
  const db = admin.firestore();

  const restaurantDoc = await db.collection("restaurants").doc(RESTAURANT_ID).get();
  if (!restaurantDoc.exists) {
    console.error(
      `[migrate_canonical_catalog_to_project] restaurants/${RESTAURANT_ID} does not exist in "${PROJECT_ID}" — ` +
        "the canonical tenant must already be provisioned first.",
    );
    process.exit(1);
  }

  let exportData;
  try {
    exportData = JSON.parse(readFileSync(EXPORT_PATH, "utf8"));
  } catch (error) {
    console.error(
      `[migrate_canonical_catalog_to_project] could not read ${EXPORT_PATH} — run ` +
        "`dart run tool/export_menu_catalog.dart` from the repo root first.",
    );
    throw error;
  }

  const result = await migrateCanonicalCatalog(db, exportData, {
    organizationId: ORGANIZATION_ID,
    restaurantId: RESTAURANT_ID,
  });
  console.log(`[migrate_canonical_catalog_to_project] project: ${PROJECT_ID}`);
  console.log(`[migrate_canonical_catalog_to_project] menuCategories: ${result.categoriesWritten} written.`);
  console.log(`[migrate_canonical_catalog_to_project] menuProducts: ${result.productsWritten} written.`);
  console.log(`[migrate_canonical_catalog_to_project] bowlIngredients: ${result.ingredientsWritten} written.`);
  console.log(
    `[migrate_canonical_catalog_to_project] channelPricingPolicies/${RESTAURANT_ID}: ` +
      `${result.channelPricingPolicyWritten ? "written" : "NOT written"}.`,
  );

  const [categoryCount, productCount, ingredientCount, policyDoc] = await Promise.all([
    db.collection("menuCategories").count().get(),
    db.collection("menuProducts").count().get(),
    db.collection("bowlIngredients").count().get(),
    db.collection("channelPricingPolicies").doc(RESTAURANT_ID).get(),
  ]);
  console.log(
    `[migrate_canonical_catalog_to_project] verified counts — categories: ${categoryCount.data().count}, ` +
      `products: ${productCount.data().count}, bowlIngredients: ${ingredientCount.data().count}, ` +
      `channelPricingPolicies/${RESTAURANT_ID} exists: ${policyDoc.exists}`,
  );

  await app.delete();
}

main().catch((error) => {
  console.error("[migrate_canonical_catalog_to_project] failed:", error);
  process.exitCode = 1;
});
