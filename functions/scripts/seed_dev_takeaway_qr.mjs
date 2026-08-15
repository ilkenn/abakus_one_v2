// Faz D.2 — reusable dev/emulator Gel Al (takeaway) QR seed.
//
// Writes a real `takeawayQrCodes` document, bound to this app's real
// canonical tenant chain (org-1 -> restaurant-1 -> branch-1 — the same
// chain `seed_dev_tenant.mjs` provisions). Requires that chain to already
// exist; run `npm run seed:dev-tenant` first.
//
// Uses the Admin SDK to write directly — this is the CORRECT, intended
// write path for `takeawayQrCodes`, not a shortcut around one: unlike
// `organizations`/`restaurants`/`branches` (which have dedicated
// `provision*` callables enforcing chain/authorization logic this phase
// built), `takeawayQrCodes` has no callable write path at all by design
// (`firestore.rules`'s fail-closed catch-all covers it, exactly like
// `tableQrCodes` before it) — Admin SDK is the only way anything, ever,
// writes to this collection. This script does not bypass any
// authorization/validation logic that exists elsewhere, because none
// exists to bypass.
//
// The token used here is a fixed, deterministic string — fine for
// dev/emulator use (matches this repo's existing `tableQrCodes` dev-seed
// precedent of readable literal tokens in tests), but a REAL production
// token generator must use a high-entropy random value (this script is
// not that generator, and was never asked to be — no production
// provisioning flow exists yet).
//
// Safe to re-run any time — uses a fixed document id, so re-running
// upserts the same document rather than creating a duplicate.
//
// SAFETY: refuses to run unless FIRESTORE_EMULATOR_HOST is set. Run via:
//
//   cd functions
//   firebase emulators:exec --only firestore,functions,auth \
//     "node scripts/seed_dev_takeaway_qr.mjs"

import admin from "firebase-admin";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    "[seed_dev_takeaway_qr] FIRESTORE_EMULATOR_HOST is not set — refusing " +
      "to run against anything but the local emulator suite. Run via " +
      '`firebase emulators:exec --only firestore,functions,auth ' +
      '"node scripts/seed_dev_takeaway_qr.mjs"`.',
  );
  process.exit(1);
}

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-abakus-one-emulator";
const ORGANIZATION_ID = "org-1";
const RESTAURANT_ID = "restaurant-1";
const BRANCH_ID = "branch-1";
const QR_CODE_ID = "dev-takeaway-qr-branch-1";
const QR_TOKEN = "DEV-TAKEAWAY-BRANCH-1-TOKEN";

const app = admin.initializeApp({ projectId: PROJECT_ID });

async function main() {
  const db = admin.firestore();

  const branchDoc = await db.collection("branches").doc(BRANCH_ID).get();
  if (!branchDoc.exists) {
    console.error(
      `[seed_dev_takeaway_qr] branches/${BRANCH_ID} does not exist — run ` +
        "`npm run seed:dev-tenant` first to provision the canonical " +
        "org-1 -> restaurant-1 -> branch-1 chain.",
    );
    process.exit(1);
  }

  const now = new Date();
  await db.collection("takeawayQrCodes").doc(QR_CODE_ID).set({
    opaqueToken: QR_TOKEN,
    organizationId: ORGANIZATION_ID,
    restaurantId: RESTAURANT_ID,
    branchId: BRANCH_ID,
    status: "active",
    createdAt: now,
    updatedAt: now,
    revision: 1,
  });

  console.log(`[seed_dev_takeaway_qr] takeawayQrCodes/${QR_CODE_ID}: provisioned.`);
  console.log(`[seed_dev_takeaway_qr] token (dev/emulator only): ${QR_TOKEN}`);

  await app.delete();
}

main().catch((error) => {
  console.error("[seed_dev_takeaway_qr] failed:", error);
  process.exitCode = 1;
});
