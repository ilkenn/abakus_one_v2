// 2026-11-13 — creates the e-mail/password sign-in used as the DEV project's
// Platform Owner for the real-device test (docs/courier_pool_device_test.md).
//
// It only creates the Firebase Auth account and prints its uid. Making it the
// Platform Owner is still `bootstrap_platform_owner.mjs <uid>`, the one
// audited, self-limiting bootstrap path; this script grants no role at all.
//
// Idempotent: an existing account is reused and its password never changes.
// A new account's generated password is printed ONCE.
//
// SAFETY: abakus-one-dev only. Refuses any other project, any emulator demo
// project, and a set FIRESTORE_EMULATOR_HOST / FIREBASE_AUTH_EMULATOR_HOST.
//
// Usage:
//   cd functions
//   GCLOUD_PROJECT=abakus-one-dev \
//   GOOGLE_APPLICATION_CREDENTIALS=<service-account.json> \
//   node scripts/create_dev_test_owner_account.mjs

import admin from "firebase-admin";
import { randomBytes } from "node:crypto";

const TAG = "[create_dev_test_owner_account]";
const EMAIL = "sahip.test@abakus.dev";

function fail(message) {
  console.error(`${TAG} ${message}`);
  process.exit(1);
}

const projectId = process.env.GCLOUD_PROJECT;
if (projectId !== "abakus-one-dev") fail(`GCLOUD_PROJECT must be "abakus-one-dev" (got "${projectId ?? ""}").`);
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) fail("GOOGLE_APPLICATION_CREDENTIALS must point to a service account key.");
if (process.env.FIRESTORE_EMULATOR_HOST || process.env.FIREBASE_AUTH_EMULATOR_HOST) {
  fail("an emulator host variable is set — unset it to target the real dev project.");
}

const app = admin.initializeApp({ projectId });

async function main() {
  const auth = admin.auth();
  let user;
  try {
    user = await auth.getUserByEmail(EMAIL);
    console.log(`${TAG} ${EMAIL}: already exists, password unchanged.`);
  } catch {
    const password = randomBytes(9).toString("base64url");
    user = await auth.createUser({ email: EMAIL, password, displayName: "Test Platform Sahibi" });
    console.log(`${TAG} ${EMAIL}: created. Password (shown once): ${password}`);
  }
  console.log(`${TAG} uid=${user.uid}`);
  await app.delete();
}

main().catch((error) => {
  console.error(`${TAG} failed:`, error);
  process.exitCode = 1;
});
