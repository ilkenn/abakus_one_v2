// Faz D.4 — real emulator end-to-end proof for the QR GUEST Gel Al
// (takeaway) flow against the FULL migrated canonical catalog.
//
// This is the guest-path counterpart to `e2e_takeaway_real_catalog.mjs`
// (Faz D.3.1's authenticated-path proof) — a human-readable, narrated
// backend proof script, not a `node --test` assertion suite. It exercises
// the exact same sequence the new Flutter QR guest UI (Faz D.4) now
// drives, at the backend level: a real public QR token ->
// `resolveTakeawayQrToken` (unauthenticated preview) -> a real anonymous
// Firebase Auth sign-in -> `openTakeawayGuestSession` -> `submitTakeawayOrder`
// (guest branch, `takeawaySessionId` only — no restaurantId/branchId/
// pickupMode/pickupTime, matching what `TakeawayGuestCheckoutScreen`
// actually sends) -> a real Firestore read-back, run once for a normal
// product and once for a bowl built from real Bowl Builder ingredients.
//
// **Why this is new, not a duplicate of D.3.1's own real-catalog test
// file**: `submitTakeawayOrderRealCatalog.test.ts` (Faz D.3.1) only
// exercises the AUTHENTICATED phone-customer scenario against the real
// catalog — the QR-GUEST scenario had only ever been proven against Faz
// D.3's small synthetic representative fixtures
// (`submitTakeawayOrder.test.ts`'s guest tests), never against the real,
// fully-migrated catalog together with a real, unauthenticated
// `resolveTakeawayQrToken` preview call and a real anonymous sign-in.
// This script closes that gap.
//
// Requires the real canonical tenant chain + real catalog + a real
// takeaway QR code already seeded — i.e. `npm run seed:dev-all` (which
// chains `seed_dev_tenant.mjs` -> `seed_dev_takeaway_qr.mjs` ->
// `migrate_canonical_catalog.mjs`). Run via:
//
//   cd functions
//   npm run seed:dev-all
//   firebase emulators:exec --only firestore,functions,auth \
//     "node scripts/e2e_takeaway_guest_real_catalog.mjs"
//
// SAFETY: refuses to run unless FIRESTORE_EMULATOR_HOST is set.

import admin from "firebase-admin";
import { readFileSync } from "fs";
import { fileURLToPath } from "url";
import { dirname, join } from "path";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    "[e2e_takeaway_guest_real_catalog] FIRESTORE_EMULATOR_HOST is not set " +
      "— refusing to run against anything but the local emulator suite.",
  );
  process.exit(1);
}

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST
  ? `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`
  : "http://127.0.0.1:9099";
const RESOLVE_URL = `${FUNCTIONS_HOST}/${PROJECT_ID}/us-central1/resolveTakeawayQrToken`;
const OPEN_SESSION_URL = `${FUNCTIONS_HOST}/${PROJECT_ID}/us-central1/openTakeawayGuestSession`;
const SUBMIT_URL = `${FUNCTIONS_HOST}/${PROJECT_ID}/us-central1/submitTakeawayOrder`;

const RESTAURANT_ID = "restaurant-1";
const BRANCH_ID = "branch-1";
// The exact dev/emulator token `scripts/seed_dev_takeaway_qr.mjs` seeds —
// see that script's own doc comment (a real production token generator
// would need high entropy; this fixed literal is dev/emulator-only, by
// design, matching this repo's existing `tableQrCodes` precedent).
const QR_TOKEN = "DEV-TAKEAWAY-BRANCH-1-TOKEN";

const __dirname = dirname(fileURLToPath(import.meta.url));
const EXPORT_PATH = join(__dirname, "data", "menu_catalog_export.json");

const app = admin.initializeApp({ projectId: PROJECT_ID });

async function callCallable(url, data, idToken) {
  const headers = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = await response.json();
  return { httpStatus: response.status, body };
}

async function createAnonymousUser() {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = await response.json();
  return { idToken: body.idToken, uid: body.localId };
}

// Faz D.4.1: a real, phone-verified customer scanning the same physical QR
// with an EXISTING auth session — proves `TechnicalIdentityProvider`'s
// "never overwrite an existing session" behavior composes correctly with
// the guest QR flow end-to-end, closing the gap the D.4 report itself
// flagged as missing (see docs/decisions.md ADR-027).
let phoneCounter = 0;
async function createRealPhoneUser() {
  phoneCounter += 1;
  const phoneNumber = `+1555555${String(3000 + phoneCounter).padStart(4, "0")}`;
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
  return { idToken: signInBody.idToken, uid: signInBody.localId, phoneNumber };
}

let keyCounter = 0;
function nextSubmissionKey() {
  keyCounter += 1;
  return `e2e-guest-key-${Date.now()}-${keyCounter}`;
}

const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz", contactPhone: "+905551112233" };

async function submitAndVerify(label, idToken, uid, takeawaySessionId, items, expectedGrandTotalMinorUnits) {
  console.log(`\n[e2e-guest] --- ${label} ---`);
  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    { submissionKey: nextSubmissionKey(), takeawaySessionId, items, ...CONTACT },
    idToken,
  );

  if (httpStatus !== 200) {
    console.error(`[e2e-guest] FAILED: httpStatus=${httpStatus}`, JSON.stringify(body));
    process.exitCode = 1;
    return;
  }

  const orderId = body.result.orderId;
  const orderDoc = await admin.firestore().collection("orders").doc(orderId).get();
  const order = orderDoc.data();

  console.log(`[e2e-guest] orderId: ${orderId}`);
  console.log(`[e2e-guest] channel=${order.channel} customerId=${order.customerId} guestAuthUid=${order.guestAuthUid}`);
  console.log(`[e2e-guest] pickupMode=${order.pickupMode} pickupTime=${order.pickupTime}`);
  console.log(`[e2e-guest] server-computed grandTotal: ${order.pricing.grandTotal.minorUnits} minorUnits`);

  const checks = {
    "channel == 'takeaway'": order.channel === "takeaway",
    "customerId == null": order.customerId === null,
    "guestAuthUid == real anonymous uid": order.guestAuthUid === uid,
    "pickupMode == 'asap'": order.pickupMode === "asap",
    "pickupTime == null": order.pickupTime === null,
    "canonical pricing correct": order.pricing.grandTotal.minorUnits === expectedGrandTotalMinorUnits,
  };
  const failed = Object.entries(checks).filter(([, ok]) => !ok);
  if (failed.length > 0) {
    console.error(
      `[e2e-guest] FAILED verification for ${label}:`,
      failed.map(([name]) => name).join(", "),
      `(expected grandTotal ${expectedGrandTotalMinorUnits}, got ${order.pricing.grandTotal.minorUnits})`,
    );
    process.exitCode = 1;
    return;
  }
  console.log(`[e2e-guest] PASS: ${label} — all invariants server-derived, none client-supplied`);
}

async function main() {
  const exportData = JSON.parse(readFileSync(EXPORT_PATH, "utf8"));

  const branchDoc = await admin.firestore().collection("branches").doc(BRANCH_ID).get();
  if (!branchDoc.exists) {
    console.error("[e2e_takeaway_guest_real_catalog] branches/branch-1 does not exist — run `npm run seed:dev-all` first.");
    process.exit(1);
  }
  const qrDoc = await admin.firestore().collection("takeawayQrCodes").doc("dev-takeaway-qr-branch-1").get();
  if (!qrDoc.exists) {
    console.error(
      "[e2e_takeaway_guest_real_catalog] takeawayQrCodes/dev-takeaway-qr-branch-1 does not exist — run " +
        "`npm run seed:dev-all` first (chains seed_dev_takeaway_qr.mjs).",
    );
    process.exit(1);
  }

  const normal = exportData.products.find((p) => p.id === "prod_crispy_falafel_salad");
  const protein = exportData.bowlIngredients.find((i) => i.id === "bb_protein_izgara_tavuk");
  const carbs = exportData.bowlIngredients.find((i) => i.id === "bb_carbs_meksika_pilavi");

  // --- Step 1: public, unauthenticated preview (resolveTakeawayQrToken) ---
  console.log("[e2e-guest] Step 1: resolveTakeawayQrToken (public, no auth header)");
  const { httpStatus: previewStatus, body: previewBody } = await callCallable(RESOLVE_URL, { token: QR_TOKEN });
  if (previewStatus !== 200 || previewBody.result?.status !== "valid") {
    console.error("[e2e-guest] FAILED: preview did not resolve to valid", JSON.stringify(previewBody));
    process.exitCode = 1;
    return;
  }
  console.log(`[e2e-guest] preview OK — branchDisplayName="${previewBody.result.branchDisplayName}" (no internal ids leaked)`);
  if (previewBody.result.organizationId || previewBody.result.restaurantId || previewBody.result.branchId) {
    console.error("[e2e-guest] FAILED: preview leaked internal scope ids — data-minimization violated");
    process.exitCode = 1;
    return;
  }

  // --- Step 2: real anonymous technical identity ---
  console.log("[e2e-guest] Step 2: real anonymous Firebase Auth sign-in");
  const { idToken, uid } = await createAnonymousUser();
  console.log(`[e2e-guest] Authenticated as anonymous technical identity, uid=${uid}`);

  // --- Step 3: openTakeawayGuestSession ---
  console.log("[e2e-guest] Step 3: openTakeawayGuestSession");
  const { httpStatus: openStatus, body: openBody } = await callCallable(
    OPEN_SESSION_URL,
    { token: QR_TOKEN },
    idToken,
  );
  if (openStatus !== 200) {
    console.error("[e2e-guest] FAILED: openTakeawayGuestSession", JSON.stringify(openBody));
    process.exitCode = 1;
    return;
  }
  const session = openBody.result;
  console.log(`[e2e-guest] session opened: sessionId=${session.sessionId} restaurantId=${session.restaurantId} branchId=${session.branchId}`);
  if (session.restaurantId !== RESTAURANT_ID || session.branchId !== BRANCH_ID) {
    console.error("[e2e-guest] FAILED: session scope did not match the expected canonical chain");
    process.exitCode = 1;
    return;
  }

  // --- Step 4/5: submitTakeawayOrder (guest branch) for a normal product, then a bowl ---
  await submitAndVerify(
    `Normal product (${normal.name})`,
    idToken,
    uid,
    session.sessionId,
    [{ kind: "product", productId: normal.id, quantity: 1 }],
    normal.basePriceMinorUnits + 2000,
  );

  const bowlExpected = protein.priceMinorUnits + carbs.priceMinorUnits + 2000;
  await submitAndVerify(
    "Bowl (real Bowl Builder ingredients)",
    idToken,
    uid,
    session.sessionId,
    [{ kind: "bowl", quantity: 1, ingredientIds: [protein.id, carbs.id] }],
    bowlExpected,
  );

  // --- Faz D.4.1 scenario: an EXISTING real, phone-verified customer scans
  // the same physical QR (their `TechnicalIdentityProvider` reuses the
  // already-signed-in session rather than overwriting it with a new
  // anonymous user) and completes the same guest checkout. ---
  console.log("\n[e2e-guest] === Faz D.4.1: existing phone-auth session through the QR guest flow ===");
  console.log("[e2e-guest] Step 1: real phone-verified Firebase Auth sign-in (simulates an ALREADY logged-in customer)");
  const phoneUser = await createRealPhoneUser();
  console.log(`[e2e-guest] Authenticated as real phone customer, uid=${phoneUser.uid}, phone=${phoneUser.phoneNumber}`);
  const beforeAuthUser = await admin.auth().getUser(phoneUser.uid);

  console.log("[e2e-guest] Step 2: resolveTakeawayQrToken (public, no identity implication)");
  const { httpStatus: phonePreviewStatus, body: phonePreviewBody } = await callCallable(RESOLVE_URL, { token: QR_TOKEN });
  if (phonePreviewStatus !== 200 || phonePreviewBody.result?.status !== "valid") {
    console.error("[e2e-guest] FAILED: preview did not resolve to valid for the phone-auth scenario", JSON.stringify(phonePreviewBody));
    process.exitCode = 1;
  } else {
    console.log("[e2e-guest] Step 3: openTakeawayGuestSession — reuses the EXISTING phone-auth uid, TechnicalIdentityProvider never overwrites it");
    const { httpStatus: phoneOpenStatus, body: phoneOpenBody } = await callCallable(
      OPEN_SESSION_URL,
      { token: QR_TOKEN },
      phoneUser.idToken,
    );
    if (phoneOpenStatus !== 200) {
      console.error("[e2e-guest] FAILED: openTakeawayGuestSession for the existing phone-auth caller", JSON.stringify(phoneOpenBody));
      process.exitCode = 1;
    } else {
      const phoneSession = phoneOpenBody.result;
      console.log(`[e2e-guest] session opened: sessionId=${phoneSession.sessionId}`);

      await submitAndVerify(
        `Existing phone-auth customer, normal product (${normal.name})`,
        phoneUser.idToken,
        phoneUser.uid,
        phoneSession.sessionId,
        [{ kind: "product", productId: normal.id, quantity: 1 }],
        normal.basePriceMinorUnits + 2000,
      );

      console.log("[e2e-guest] Step 4: verifying the underlying Firebase Auth identity was never touched by the guest order");
      const afterAuthUser = await admin.auth().getUser(phoneUser.uid);
      const identityChecks = {
        "uid unchanged": afterAuthUser.uid === beforeAuthUser.uid,
        "phoneNumber unchanged": afterAuthUser.phoneNumber === beforeAuthUser.phoneNumber,
        "still phone-provider-backed": afterAuthUser.providerData[0]?.providerId === "phone",
      };
      const failedIdentityChecks = Object.entries(identityChecks).filter(([, ok]) => !ok);
      if (failedIdentityChecks.length > 0) {
        console.error("[e2e-guest] FAILED: existing phone-auth identity was altered by the QR guest flow:", failedIdentityChecks.map(([n]) => n).join(", "));
        process.exitCode = 1;
      } else {
        console.log("[e2e-guest] PASS: existing phone-auth session left completely intact — not signed out, not overwritten, not converted to a customer order");
      }

      const customerDoc = await admin.firestore().collection("customers").doc(phoneUser.uid).get();
      if (customerDoc.exists) {
        console.error("[e2e-guest] FAILED: a customers/{uid} CRM document was unexpectedly created for the QR guest order");
        process.exitCode = 1;
      } else {
        console.log("[e2e-guest] PASS: no customers/{uid} CRM record created — no loyalty/Boncuk implication");
      }
    }
  }

  if (process.exitCode === 1) {
    console.error("\n[e2e-guest] FAILED — see above.");
  } else {
    console.log(
      "\n[e2e-guest] Full QR guest flow PASSED end-to-end for BOTH scenarios: (1) a fresh anonymous " +
        "technical identity, and (2) an existing real phone-verified customer whose session is reused, " +
        "never overwritten — public preview -> auth -> guest session -> real-catalog order submission " +
        "-> Firestore read-back.",
    );
  }

  await app.delete();
}

main().catch((error) => {
  console.error("[e2e_takeaway_guest_real_catalog] failed:", error);
  process.exitCode = 1;
});
