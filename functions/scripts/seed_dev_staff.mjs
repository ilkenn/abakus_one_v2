// Faz R.3A — dev/emulator seed for the canonical Abaküs owner/admin
// development account, so R.3A's admin reservation UI (and any other
// manageReservations/manageBranch-gated screen) can be exercised
// end-to-end by a real, signed-in Firebase user in local development —
// never only by tests injecting custom claims directly.
//
// Routes through the real callables (`bootstrapFirstAdminAccount`,
// `syncOwnStaffClaims`), never a direct Firestore write — mirrors
// `seed_dev_tenant.mjs`'s own stated preference exactly: this script
// cannot silently produce a membership shape the callables themselves
// would have rejected.
//
// Requires org-1 to already be provisioned — run `seed_dev_tenant.mjs`
// first (or via `npm run seed:dev-tenant`, which already does).
//
// Safe to re-run: if org-1 already has a membership (this script's own
// prior run, or any other), `bootstrapFirstAdminAccount` fails closed with
// `failed-precondition` and this script treats that as "already seeded,"
// not an error — it never overwrites an existing membership.
//
// SAFETY: refuses to run unless FIRESTORE_EMULATOR_HOST is set. Run via:
//
//   cd functions
//   firebase emulators:exec --only firestore,functions,auth \
//     "node scripts/seed_dev_tenant.mjs && node scripts/seed_dev_staff.mjs"

import admin from "firebase-admin";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  console.error(
    "[seed_dev_staff] FIRESTORE_EMULATOR_HOST is not set — refusing to run. " +
      "This script creates a real email/password dev admin account and must " +
      "only ever run against the local emulator suite, never a real Firebase " +
      "project.",
  );
  process.exit(1);
}

const PROJECT_ID = process.env.GCLOUD_PROJECT || "demo-abakus-one-emulator";
const AUTH_HOST = process.env.FIREBASE_AUTH_EMULATOR_HOST
  ? `http://${process.env.FIREBASE_AUTH_EMULATOR_HOST}`
  : "http://127.0.0.1:9099";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const BOOTSTRAP_URL = `${FUNCTIONS_HOST}/${PROJECT_ID}/us-central1/bootstrapFirstAdminAccount`;
const SYNC_CLAIMS_URL = `${FUNCTIONS_HOST}/${PROJECT_ID}/us-central1/syncOwnStaffClaims`;

// A dev-only placeholder domain (mirrors this codebase's own `.test`/`.dev`
// convention for non-real addresses in tests/fixtures) — never a real
// mailbox, never used outside the local emulator.
const DEV_ADMIN_EMAIL = "admin@abakus.dev";
const DEV_ADMIN_PASSWORD = "abakus-dev-admin-2026";
const ORGANIZATION_ID = "org-1";

const app = admin.initializeApp({ projectId: PROJECT_ID });

async function callCallable(url, data, idToken) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${idToken}` },
    body: JSON.stringify({ data }),
  });
  return { httpStatus: response.status, body: await response.json() };
}

async function signUpOrSignInWithEmail(email, password) {
  const signUpRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const signUpBody = await signUpRes.json();
  if (signUpBody.idToken) {
    return { idToken: signUpBody.idToken, refreshToken: signUpBody.refreshToken, uid: signUpBody.localId, created: true };
  }
  // EMAIL_EXISTS on a re-run — sign in instead, same account.
  const signInRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const signInBody = await signInRes.json();
  if (!signInBody.idToken) {
    throw new Error(`[seed_dev_staff] could not sign up or sign in ${email}: ${JSON.stringify(signInBody)}`);
  }
  return { idToken: signInBody.idToken, refreshToken: signInBody.refreshToken, uid: signInBody.localId, created: false };
}

async function main() {
  console.log(`[seed_dev_staff] seeding dev admin account "${DEV_ADMIN_EMAIL}" for organization "${ORGANIZATION_ID}"...`);

  const { idToken, uid, created } = await signUpOrSignInWithEmail(DEV_ADMIN_EMAIL, DEV_ADMIN_PASSWORD);
  console.log(`[seed_dev_staff] Firebase Auth account: ${created ? "created" : "already existed (signed in)"} (uid=${uid})`);

  const bootstrap = await callCallable(BOOTSTRAP_URL, { organizationId: ORGANIZATION_ID }, idToken);
  if (bootstrap.httpStatus === 200) {
    console.log(`[seed_dev_staff] memberships/${ORGANIZATION_ID}_${uid}: bootstrapped as admin.`);
  } else if (bootstrap.body?.error?.status === "FAILED_PRECONDITION") {
    console.log(`[seed_dev_staff] organization "${ORGANIZATION_ID}" already has a membership — skipping bootstrap (already seeded).`);
  } else {
    throw new Error(`[seed_dev_staff] bootstrapFirstAdminAccount failed: ${JSON.stringify(bootstrap.body)}`);
  }

  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  if (sync.httpStatus !== 200) {
    throw new Error(`[seed_dev_staff] syncOwnStaffClaims failed: ${JSON.stringify(sync.body)}`);
  }
  console.log("[seed_dev_staff] custom claims synced.");

  console.log(
    `[seed_dev_staff] done. Sign in to the admin app with email="${DEV_ADMIN_EMAIL}" password="${DEV_ADMIN_PASSWORD}" ` +
      "against the local emulator, then call syncOwnStaffClaims + force a token refresh " +
      "(getIdToken(true)) before using any manageReservations/manageBranch screen.",
  );
  await app.delete();
}

main().catch((error) => {
  console.error("[seed_dev_staff] failed:", error);
  process.exitCode = 1;
});
