// Faz D.1 / D.1.1 — reusable dev/emulator canonical tenant seed.
//
// Provisions the app's single seeded tenant (org-1 -> restaurant-1 ->
// branch-1 — the exact same ids/names/supportedOrderChannelIds
// `lib/features/admin/presentation/providers/admin_dependencies_provider.dart`'s
// in-memory seed already uses) as REAL Firestore documents, in canonical
// order, via the real `provisionOrganization`/`provisionRestaurant`/
// `provisionBranch` callables — never by writing to Firestore directly.
// Routing through the callables (rather than an Admin-SDK direct write)
// means this script exercises the exact same chain-verification/
// idempotency logic those functions' own tests cover; it cannot silently
// produce a document shape the functions themselves would have rejected —
// in particular, `provisionRestaurant` now requires `organizations/org-1`
// to already exist and be active (Faz D.1.1), so provisioning out of
// order would fail exactly as it should for any other caller.
//
// Safe to re-run any time — all three provision* functions are idempotent
// (`.set()`-based upsert on a deterministic id).
//
// SAFETY: refuses to run unless FIRESTORE_EMULATOR_HOST is set — this
// script signs up a throwaway anonymous user and grants it a
// `platformOwner` custom claim directly via the Admin SDK, which must
// never happen against a real Firebase project. Run it via:
//
//   cd functions
//   firebase emulators:exec --only firestore,functions,auth \
//     "node scripts/seed_dev_tenant.mjs"
//
// or, against an already-running local emulator suite, with
// FIRESTORE_EMULATOR_HOST/FIREBASE_AUTH_EMULATOR_HOST/FUNCTIONS_EMULATOR_HOST
// already exported in the shell.

import admin from "firebase-admin";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    "[seed_dev_tenant] FIRESTORE_EMULATOR_HOST is not set — refusing to " +
      "run. This script grants a platformOwner claim to a throwaway user " +
      "and must only ever run against the local emulator suite, never a " +
      "real Firebase project. Run via `firebase emulators:exec " +
      '--only firestore,functions,auth "node scripts/seed_dev_tenant.mjs"`.',
  );
  process.exit(1);
}

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-abakus-one-emulator";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST
  ? `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`
  : "http://127.0.0.1:9099";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const PROVISION_ORGANIZATION_URL =
  `${FUNCTIONS_HOST}/${PROJECT_ID}/us-central1/provisionOrganization`;
const PROVISION_RESTAURANT_URL =
  `${FUNCTIONS_HOST}/${PROJECT_ID}/us-central1/provisionRestaurant`;
const PROVISION_BRANCH_URL =
  `${FUNCTIONS_HOST}/${PROJECT_ID}/us-central1/provisionBranch`;

const app = admin.initializeApp({ projectId: PROJECT_ID });

async function callCallable(url, data, idToken) {
  const response = await fetch(url, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${idToken}`,
    },
    body: JSON.stringify({ data }),
  });
  const body = await response.json();
  if (body.error) {
    throw new Error(
      `${url} failed: ${body.error.status} — ${body.error.message}`,
    );
  }
  return body.result;
}

async function mintPlatformOwnerIdToken() {
  const signUpRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const signUpBody = await signUpRes.json();
  const { localId: uid, refreshToken } = signUpBody;

  await admin.auth().setCustomUserClaims(uid, { platformRole: "platformOwner" });

  const refreshRes = await fetch(
    `${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "refresh_token",
        refresh_token: refreshToken,
      }).toString(),
    },
  );
  const refreshBody = await refreshRes.json();
  return refreshBody.id_token;
}

async function main() {
  console.log(`[seed_dev_tenant] provisioning canonical tenant in project "${PROJECT_ID}"...`);
  const idToken = await mintPlatformOwnerIdToken();

  const organization = await callCallable(
    PROVISION_ORGANIZATION_URL,
    { organizationId: "org-1", name: "Abaküs" },
    idToken,
  );
  console.log(
    `[seed_dev_tenant] organizations/org-1: ${organization.created ? "created" : "already existed (upserted)"}`,
  );

  const restaurant = await callCallable(
    PROVISION_RESTAURANT_URL,
    {
      organizationId: "org-1",
      restaurantId: "restaurant-1",
      name: "Abaküs Bowl",
    },
    idToken,
  );
  console.log(
    `[seed_dev_tenant] restaurants/restaurant-1: ${restaurant.created ? "created" : "already existed (upserted)"}`,
  );

  const branch = await callCallable(
    PROVISION_BRANCH_URL,
    {
      organizationId: "org-1",
      restaurantId: "restaurant-1",
      branchId: "branch-1",
      name: "Merkez Şube",
      supportedOrderChannelIds: ["dineInQr", "dineInStaff", "delivery", "takeaway"],
    },
    idToken,
  );
  console.log(
    `[seed_dev_tenant] branches/branch-1: ${branch.created ? "created" : "already existed (upserted)"}`,
  );

  console.log("[seed_dev_tenant] done.");
  await app.delete();
}

main().catch((error) => {
  console.error("[seed_dev_tenant] failed:", error);
  process.exitCode = 1;
});
