// Boncuk Loyalty Program P7-B (2026-08-24) — reusable dev/emulator seed for
// the four LOCKED initial Reward Catalog entries. Calls the real,
// server-authoritative `createLoyaltyReward` (compiled output, imported via
// `createRequire` — the same robust CommonJS-from-ESM pattern
// `migrate_canonical_catalog.mjs` already established for this codebase's
// scripts) rather than writing to Firestore directly — this script cannot
// silently produce a shape the function itself would reject, and every
// product-existence/organization-ownership check the function performs
// runs for real against this emulator's own canonical catalog.
//
// Bound to this app's real canonical tenant chain (org-1 -> restaurant-1 ->
// branch-1 — requires `npm run seed:dev-tenant` and the canonical menu
// catalog (`migrate_canonical_catalog.mjs`) to already exist, since every
// eligible product id below must resolve against a real `menuProducts`
// document).
//
// Idempotent by construction: `createLoyaltyReward` itself is a safe no-op
// when `rewardId` already exists (returns the existing version untouched,
// `created: false`) — re-running this script never creates a duplicate
// logical reward or a duplicate version doc.
//
// SAFETY: refuses to run unless FIRESTORE_EMULATOR_HOST is set — the same
// sole safety gate every other seed script in this codebase already uses
// (seed_dev_tenant.mjs, seed_dev_reservation.mjs, seed_dev_catalog.mjs).
// Also prints the resolved project id prominently before writing anything,
// so a operator can positively confirm the emulator target before
// proceeding — deliberately not a second blocking mechanism beyond the
// established FIRESTORE_EMULATOR_HOST convention, just an explicit,
// visible confirmation line. Run via:
//
//   cd functions
//   export FIRESTORE_EMULATOR_HOST=127.0.0.1:8080
//   export GCLOUD_PROJECT=abakus-one-dev
//   node scripts/seed_dev_loyalty_reward_catalog.mjs
//
// or, for the automated test-suite's own isolated emulator instance:
//   firebase emulators:exec --only firestore,functions,auth \
//     "node scripts/seed_dev_tenant.mjs && node scripts/migrate_canonical_catalog.mjs && node scripts/seed_dev_loyalty_reward_catalog.mjs"

import admin from "firebase-admin";
import { createRequire } from "module";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    "[seed_dev_loyalty_reward_catalog] FIRESTORE_EMULATOR_HOST is not set — " +
      "refusing to run against anything but the local emulator suite.",
  );
  process.exit(1);
}

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-abakus-one-emulator";
const ORGANIZATION_ID = "org-1";

console.log(
  `[seed_dev_loyalty_reward_catalog] target project (POSITIVELY VERIFY this is the local emulator, never production): "${PROJECT_ID}"`,
);

const app = admin.initializeApp({ projectId: PROJECT_ID });
const db = admin.firestore();

const require = createRequire(import.meta.url);
const { createLoyaltyReward } = require("../lib/loyaltyRewardCatalogAdminService.js");

// LOCKED initial rewards (Boncuklarım P7-B, 2026-08-24). Every
// `eligibleProductIds` entry is an exact canonical `menuProducts` document
// id resolved directly from the live canonical catalog — never guessed.
// "Crispy Chicken Fettuccine"/"Falafel Salad" (the task's own requested
// names) map to the sole matching canonical products
// ("Fettucine Crispy Chicken Alfredo"/"Crispy Falafel Salad" respectively)
// — each is the ONLY product in the entire 79-item catalog whose name
// contains both required keywords ("crispy"+"chicken"+"fettuccine";
// "falafel" within the Salata category), a deterministic, unambiguous
// resolution, not an invented one. See docs/decisions.md's P7-B entry for
// the full resolution reasoning.
const INITIAL_REWARDS = [
  {
    rewardId: "icecek",
    title: "İçecek",
    description:
      "70 Boncuk karşılığında seçili içeceklerden birini alın: Acılı Ayran, Ekşili Ayran, Naneli Ayran veya CocaCola Şişe.",
    rewardType: "explicitProductSet",
    eligibleProductIds: [
      "prod_acili_ayran",
      "prod_cocacola",
      "prod_eksili_ayran",
      "prod_naneli_ayran",
    ],
    eligibleChannels: ["dineIn", "takeaway", "delivery", "reservationPreorder"],
    boncukCost: 70,
    sortOrder: 0,
  },
  {
    rewardId: "citirti-bowl",
    title: "Çıtırtı Bowl",
    description: "420 Boncuk karşılığında bir Çıtırtı Bowl alın.",
    rewardType: "explicitProductSet",
    eligibleProductIds: ["prod_citirti_bowl"],
    eligibleChannels: ["dineIn", "takeaway", "delivery", "reservationPreorder"],
    boncukCost: 420,
    sortOrder: 1,
  },
  {
    rewardId: "crispy-chicken-fettuccine",
    title: "Crispy Chicken Fettuccine",
    description:
      "400 Boncuk karşılığında bir Crispy Chicken Fettuccine (menüdeki adıyla \"Fettucine Crispy Chicken Alfredo\") alın.",
    rewardType: "explicitProductSet",
    eligibleProductIds: ["prod_fettucine_crispy_chicken_alfredo"],
    eligibleChannels: ["dineIn", "takeaway", "delivery", "reservationPreorder"],
    boncukCost: 400,
    sortOrder: 2,
  },
  {
    rewardId: "falafel-salad",
    title: "Falafel Salad",
    description:
      "400 Boncuk karşılığında bir Falafel Salad (menüdeki adıyla \"Crispy Falafel Salad\") alın.",
    rewardType: "explicitProductSet",
    eligibleProductIds: ["prod_crispy_falafel_salad"],
    eligibleChannels: ["dineIn", "takeaway", "delivery", "reservationPreorder"],
    boncukCost: 400,
    sortOrder: 3,
  },
];

async function main() {
  for (const reward of INITIAL_REWARDS) {
    const result = await createLoyaltyReward(db, {
      organizationId: ORGANIZATION_ID,
      ...reward,
    });
    console.log(
      `[seed_dev_loyalty_reward_catalog] ${result.rewardId}: version ${result.version}` +
        (result.created ? " (created)" : " (already existed — idempotent no-op)"),
    );
  }
  await app.delete();
}

main().catch((error) => {
  console.error("[seed_dev_loyalty_reward_catalog] failed:", error);
  process.exitCode = 1;
});
