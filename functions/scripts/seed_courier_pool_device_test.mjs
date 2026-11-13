// 2026-11-12 (Faz 3c) — real-device test data for the courier pool + FCM
// (docs/courier_pool_device_test.md, ADR-078), for the DEV project only.
//
// What it writes (idempotent: fixed ids / fixed e-mails; re-running reuses
// existing accounts and never changes their password):
//   - deliveryServiceAreas for the branch: Kadıköy → Caferağa / Moda /
//     Fenerbahçe (so a POS phone order in those neighborhoods resolves the
//     pool district "kadikoy");
//   - five e-mail/password sign-ins with active memberships in the
//     organization: a Müdür and a Kasiyer (branch access), and three couriers
//     (no branch access — external couriers are region-based). Generated
//     passwords are printed ONCE for new accounts.
//
// What it deliberately does NOT do: create `couriers` records or link a
// sign-in to one — the test does that on the POS ("Kurye Ayarları"), which
// is exactly what Faz 3b built and what the test must exercise.
//
// SAFETY: refuses the production project (`abakusone`) and any emulator
// demo project; requires an explicit GCLOUD_PROJECT and a service account
// (GOOGLE_APPLICATION_CREDENTIALS). Never run without the product owner's
// explicit go-ahead for that run.
//
// Usage:
//   cd functions
//   GCLOUD_PROJECT=abakus-one-dev \
//   GOOGLE_APPLICATION_CREDENTIALS=<service-account.json> \
//   node scripts/seed_courier_pool_device_test.mjs <organizationId> <branchId> <restaurantId>

import admin from "firebase-admin";
import { randomBytes } from "node:crypto";

const TAG = "[seed_courier_pool_device_test]";
function fail(message) {
  console.error(`${TAG} ${message}`);
  process.exit(1);
}

const projectId = process.env.GCLOUD_PROJECT;
if (!projectId) fail("GCLOUD_PROJECT must be set (e.g. abakus-one-dev).");
if (projectId.startsWith("demo-")) fail(`"${projectId}" is an emulator demo project — this script is for the dev project.`);
if (projectId === "abakusone") fail("refusing to run against PRODUCTION (abakusone).");
if (!process.env.GOOGLE_APPLICATION_CREDENTIALS) fail("GOOGLE_APPLICATION_CREDENTIALS must point to a service account key.");
if (process.env.FIRESTORE_EMULATOR_HOST) fail("FIRESTORE_EMULATOR_HOST is set — unset it to target the real dev project.");

const [organizationId, branchId, restaurantId] = process.argv.slice(2);
if (!organizationId || !branchId || !restaurantId) {
  fail("usage: node scripts/seed_courier_pool_device_test.mjs <organizationId> <branchId> <restaurantId>");
}

const app = admin.initializeApp({ projectId });
const db = admin.firestore();
const auth = admin.auth();

// 2026-11-13 (Faz 4, ADR-081): each area also carries a test minimum basket
// and delivery estimate, so the below-minimum warning and the slip ETA can be
// checked on the device. Caferağa and Moda have a minimum; Fenerbahçe has
// none (ungated) but still an ETA.
const AREAS = [
  { districtId: "kadikoy", neighborhoodId: "caferaga", neighborhoodName: "Caferağa", minimumOrderMinorUnits: 25000, estimatedDeliveryMinutes: 35 },
  { districtId: "kadikoy", neighborhoodId: "moda", neighborhoodName: "Moda", minimumOrderMinorUnits: 30000, estimatedDeliveryMinutes: 40 },
  { districtId: "kadikoy", neighborhoodId: "fenerbahce", neighborhoodName: "Fenerbahçe", minimumOrderMinorUnits: 0, estimatedDeliveryMinutes: 30 },
];

const ACCOUNTS = [
  { key: "mudur", email: "mudur.test@abakus.dev", roles: ["manager"], branchAccess: [branchId], name: "Test Müdür" },
  { key: "kasiyer", email: "kasiyer.test@abakus.dev", roles: ["cashier"], branchAccess: [branchId], name: "Test Kasiyer" },
  { key: "dukkan-kurye", email: "kurye.dukkan@abakus.dev", roles: ["courier"], branchAccess: [], name: "Dükkan Kuryesi" },
  { key: "dis-kurye-1", email: "kurye.dis1@abakus.dev", roles: ["courier"], branchAccess: [], name: "Dış Kurye 1" },
  { key: "dis-kurye-2", email: "kurye.dis2@abakus.dev", roles: ["courier"], branchAccess: [], name: "Dış Kurye 2" },
];

async function main() {
  const branch = await db.collection("branches").doc(branchId).get();
  if (!branch.exists || branch.data().organizationId !== organizationId) {
    fail(`branch "${branchId}" does not exist in organization "${organizationId}" on ${projectId}.`);
  }

  for (const area of AREAS) {
    const id = `${branchId}_${area.districtId}_${area.neighborhoodId}`;
    // merge: a rule later edited on the POS (Teslimat Bölgeleri) keeps its
    // own audit fields; a re-run resets only the test values below.
    await db.collection("deliveryServiceAreas").doc(id).set({
      organizationId, restaurantId, branchId, ...area, enabled: true,
    }, { merge: true });
    console.log(`${TAG} deliveryServiceAreas/${id}`);
  }

  // The POS zone editor needs a default district when none is typed (ADR-081).
  if (!branch.data().defaultDeliveryDistrictId) {
    await branch.ref.update({ defaultDeliveryDistrictId: "kadikoy" });
    console.log(`${TAG} branches/${branchId}.defaultDeliveryDistrictId = kadikoy`);
  }

  const created = [];
  for (const account of ACCOUNTS) {
    let user;
    try {
      user = await auth.getUserByEmail(account.email);
      console.log(`${TAG} ${account.email}: already exists (uid=${user.uid}), password unchanged.`);
    } catch {
      const password = randomBytes(9).toString("base64url");
      user = await auth.createUser({ email: account.email, password, displayName: account.name });
      created.push({ email: account.email, password });
      console.log(`${TAG} ${account.email}: created (uid=${user.uid}).`);
    }
    await db.collection("memberships").doc(`${organizationId}_${user.uid}`).set({
      organizationId,
      uid: user.uid,
      roles: account.roles,
      branchAccess: account.branchAccess,
      restaurantAccess: [],
      status: "active",
      version: 1,
    }, { merge: true });
  }

  if (created.length > 0) {
    console.log(`\n${TAG} NEW sign-ins (shown once — keep them safe):`);
    for (const c of created) console.log(`  ${c.email}  ${c.password}`);
  }
  console.log(`\n${TAG} done. Each account's claims sync on its first sign-in in the app.`);
  await app.delete();
}

main().catch((error) => {
  console.error(`${TAG} failed:`, error);
  process.exitCode = 1;
});
