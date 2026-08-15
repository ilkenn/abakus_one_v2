// Faz D.3.1 — real emulator end-to-end proof for the authenticated Gel Al
// (takeaway) flow against the FULL migrated canonical catalog.
//
// This is deliberately NOT a `node --test` assertion suite (that
// coverage already exists in `src/test/submitTakeawayOrderRealCatalog.test.ts`
// and `src/test/catalogMigration.test.ts`) — it is a human-readable,
// narrated proof script: real phone auth -> real Gel Al branch
// (`branch-1`) -> a real, migrated menu product -> `submitTakeawayOrder`
// -> a real Firestore read-back, run once for a normal product, once for
// a beverage, and once for a bowl built from real Bowl Builder
// ingredients — printing the server-computed price at every step so a
// human can visually confirm server-authoritative pricing end-to-end,
// not just an automated assertion.
//
// Critically, all three items below are chosen to NOT be among Faz D.3's
// own small representative fixture ids (`seed_dev_catalog.mjs`:
// prod_mexifit_bowl, prod_ayran, prod_fixed_override_example,
// prod_explicit_override_example, prod_inactive_example, bowl_ing_*) —
// proving the FULL catalog migration (Faz D.3.1), not just D.3's
// pre-existing representative subset, is what is actually serving these
// orders.
//
// Requires the real canonical tenant chain + real catalog already
// migrated — i.e. `npm run seed:dev-all` (which now provisions
// `channelPricingPolicies/restaurant-1` itself, Faz D.3.1.1 — no separate
// `seed_dev_catalog.mjs` step is needed or run here). Run via:
//
//   cd functions
//   npm run seed:dev-all
//   firebase emulators:exec --only firestore,functions,auth \
//     "node scripts/e2e_takeaway_real_catalog.mjs"
//
// (or chain it directly onto the same `seed:dev-all` emulator session —
// see `package.json`'s `seed:dev-all` script for the exact chain.)
//
// SAFETY: refuses to run unless FIRESTORE_EMULATOR_HOST is set.

import admin from "firebase-admin";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    "[e2e_takeaway_real_catalog] FIRESTORE_EMULATOR_HOST is not set — " +
      "refusing to run against anything but the local emulator suite.",
  );
  process.exit(1);
}

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST
  ? `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`
  : "http://127.0.0.1:9099";
const SUBMIT_URL = `${FUNCTIONS_HOST}/${PROJECT_ID}/us-central1/submitTakeawayOrder`;

const RESTAURANT_ID = "restaurant-1";
const BRANCH_ID = "branch-1";

const __dirname = dirname(fileURLToPath(import.meta.url));
const EXPORT_PATH = join(__dirname, "data", "menu_catalog_export.json");

// The exact ids Faz D.3's own representative fixture (`seed_dev_catalog.mjs`)
// hand-seeded — deliberately excluded below so this script can only ever
// pick items that prove the FULL real migration, not D.3's small subset.
const D3_FIXTURE_IDS = new Set([
  "prod_mexifit_bowl",
  "prod_ayran",
  "prod_fixed_override_example",
  "prod_explicit_override_example",
  "prod_inactive_example",
  "bowl_ing_chicken",
  "bowl_ing_falafel",
  "bowl_ing_rice",
  "bowl_ing_yogurt_sauce",
  "bowl_ing_inactive",
]);

const app = admin.initializeApp({ projectId: PROJECT_ID });

async function callSubmit(data, idToken) {
  const response = await fetch(SUBMIT_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${idToken}` },
    body: JSON.stringify({ data }),
  });
  const body = await response.json();
  return { httpStatus: response.status, body };
}

let phoneCounter = 0;
async function createRealPhoneUser() {
  phoneCounter += 1;
  const phoneNumber = `+1555556${String(4000 + phoneCounter).padStart(4, "0")}`;
  const sendRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ phoneNumber, recaptchaToken: "ignored-by-emulator" }),
    },
  );
  const sendBody = await sendRes.json();
  const codesRes = await fetch(`${AUTH_HOST}/emulator/v1/projects/${PROJECT_ID}/verificationCodes`);
  const codesBody = await codesRes.json();
  const match = codesBody.verificationCodes.find((c) => c.sessionInfo === sendBody.sessionInfo);
  const signInRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }),
    },
  );
  const signInBody = await signInRes.json();
  return { idToken: signInBody.idToken, uid: signInBody.localId };
}

function futurePickupIso(minutesFromNow) {
  return new Date(Date.now() + minutesFromNow * 60 * 1000).toISOString();
}

let keyCounter = 0;
function nextSubmissionKey() {
  keyCounter += 1;
  return `e2e-key-${Date.now()}-${keyCounter}`;
}

const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz", contactPhone: "+905551112233" };

async function submitAndVerify(label, idToken, uid, items, expectedGrandTotalMinorUnits) {
  console.log(`\n[e2e] --- ${label} ---`);
  const { httpStatus, body } = await callSubmit(
    {
      submissionKey: nextSubmissionKey(),
      restaurantId: RESTAURANT_ID,
      branchId: BRANCH_ID,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items,
      ...CONTACT,
    },
    idToken,
  );

  if (httpStatus !== 200) {
    console.error(`[e2e] FAILED: httpStatus=${httpStatus}`, JSON.stringify(body));
    process.exitCode = 1;
    return;
  }

  const orderId = body.result.orderId;
  const orderDoc = await admin.firestore().collection("orders").doc(orderId).get();
  const order = orderDoc.data();

  console.log(`[e2e] orderId: ${orderId}`);
  console.log(`[e2e] customerId (server-derived): ${order.customerId} (expected uid: ${uid})`);
  console.log(`[e2e] server-computed grandTotal: ${order.pricing.grandTotal.minorUnits} minorUnits`);
  console.log(
    `[e2e] lines:`,
    JSON.stringify(order.lines.map((l) => ({ name: l.productName, quantity: l.quantity, unitPrice: l.unitPrice.minorUnits }))),
  );

  const okCustomer = order.customerId === uid;
  const okTotal = order.pricing.grandTotal.minorUnits === expectedGrandTotalMinorUnits;
  if (!okCustomer || !okTotal) {
    console.error(
      `[e2e] FAILED verification: customerId match=${okCustomer}, grandTotal match=${okTotal} ` +
        `(expected ${expectedGrandTotalMinorUnits}, got ${order.pricing.grandTotal.minorUnits})`,
    );
    process.exitCode = 1;
    return;
  }
  console.log(`[e2e] PASS: ${label}`);
}

async function main() {
  const exportData = JSON.parse(readFileSync(EXPORT_PATH, "utf8"));

  const branchDoc = await admin.firestore().collection("branches").doc(BRANCH_ID).get();
  if (!branchDoc.exists) {
    console.error(
      "[e2e_takeaway_real_catalog] branches/branch-1 does not exist — run " +
        "`npm run seed:dev-all` first.",
    );
    process.exit(1);
  }
  const policyDoc = await admin.firestore().collection("channelPricingPolicies").doc(RESTAURANT_ID).get();
  if (!policyDoc.exists) {
    console.error(
      "[e2e_takeaway_real_catalog] channelPricingPolicies/restaurant-1 does not exist — run " +
        "`npm run seed:dev-all` first (migrate_canonical_catalog.mjs provisions the real Faz A " +
        "pricing policy as part of the catalog migration, Faz D.3.1.1).",
    );
    process.exit(1);
  }

  const productSnap = await admin.firestore().collection("menuProducts").doc("prod_crispy_falafel_salad").get();
  if (!productSnap.exists) {
    console.error(
      "[e2e_takeaway_real_catalog] menuProducts/prod_crispy_falafel_salad does not exist — run " +
        "`npm run seed:dev-all` first (full real catalog migration).",
    );
    process.exit(1);
  }

  const normal = exportData.products.find((p) => p.id === "prod_crispy_falafel_salad");
  const drink = exportData.products.find((p) => p.id === "prod_acili_ayran");
  const protein = exportData.bowlIngredients.find((i) => i.id === "bb_protein_izgara_tavuk");
  const carbs = exportData.bowlIngredients.find((i) => i.id === "bb_carbs_meksika_pilavi");

  for (const id of [normal.id, drink.id, protein.id, carbs.id]) {
    if (D3_FIXTURE_IDS.has(id)) {
      throw new Error(`[e2e] ${id} is a Faz D.3 fixture id — this script must only use non-fixture real ids`);
    }
  }
  console.log(
    "[e2e] Selected real catalog items (none are Faz D.3 representative-fixture ids):\n" +
      `  normal product: ${normal.id} (${normal.name}, base ${normal.basePriceMinorUnits})\n` +
      `  beverage:       ${drink.id} (${drink.name}, base ${drink.basePriceMinorUnits})\n` +
      `  bowl ingredients: ${protein.id} (${protein.priceMinorUnits}) + ${carbs.id} (${carbs.priceMinorUnits})`,
  );

  const { idToken, uid } = await createRealPhoneUser();
  console.log(`[e2e] Authenticated as real phone customer, uid=${uid}`);

  // Normal product: basePrice + Faz A default takeaway adjustment (+20 TL / 2000 minorUnits).
  await submitAndVerify(
    `Normal product (${normal.name})`,
    idToken,
    uid,
    [{ kind: "product", productId: normal.id, quantity: 1 }],
    normal.basePriceMinorUnits + 2000,
  );

  // Beverage: cat_icecekler category override -> +0, price unchanged.
  await submitAndVerify(
    `Beverage (${drink.name})`,
    idToken,
    uid,
    [{ kind: "product", productId: drink.id, quantity: 1 }],
    drink.basePriceMinorUnits,
  );

  // Bowl: unitPrice is the +20 TL channel adjustment only; ingredient
  // total lives in modifiers — grandTotal = ingredients + 2000, once.
  const bowlExpected = protein.priceMinorUnits + carbs.priceMinorUnits + 2000;
  await submitAndVerify(
    "Bowl (real Bowl Builder ingredients)",
    idToken,
    uid,
    [{ kind: "bowl", quantity: 1, ingredientIds: [protein.id, carbs.id] }],
    bowlExpected,
  );

  if (process.exitCode === 1) {
    console.error("\n[e2e] FAILED — see above.");
  } else {
    console.log("\n[e2e] All three real-catalog scenarios PASSED — full canonical catalog migration proven end-to-end.");
  }

  await app.delete();
}

main().catch((error) => {
  console.error("[e2e_takeaway_real_catalog] failed:", error);
  process.exitCode = 1;
});
