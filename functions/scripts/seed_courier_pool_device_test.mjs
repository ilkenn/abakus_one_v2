// 2026-11-12 (Faz 3c) — real-device test data for the courier pool + FCM
// (docs/courier_pool_device_test.md, ADR-078), for the DEV project only.
//
// What it writes (idempotent: fixed ids / fixed e-mails; re-running reuses
// existing accounts and never changes their password):
//   - deliveryServiceAreas for the branch: Kadıköy → Caferağa / Moda /
//     Fenerbahçe (so a POS phone order in those neighborhoods resolves the
//     pool district "kadikoy");
//   - staff sign-ins with active memberships in the organization: a Yönetici,
//     a Müdür and a Kasiyer (branch access), and three couriers (no branch
//     access — external couriers are region-based). Since ADR-085 (revision,
//     2026-11-13) staff sign in with PHONE NUMBER + PASSWORD: each account
//     carries a fixed test phone number and the hidden sign-in e-mail derived
//     from it. An account created earlier with a plain e-mail is moved to its
//     phone number in place (same uid, same password). Generated passwords
//     are printed ONCE for new accounts. The dev Platform Owner keeps its
//     e-mail sign-in, which the Platform Konsolu uses.
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

// Must match staffLoginEmailForPhone in src/staffAccounts.ts (ADR-085).
function staffLoginEmailForPhone(phoneNumber) {
  return `${phoneNumber.replace(/^\+/, "")}@staff-login.abakus.invalid`;
}

// Test phone numbers (+90 555 000 00 0x) exist only in the dev project. They
// sign in with a password, never by SMS. `legacyEmail` is the plain e-mail
// an account was created with before ADR-085; such an account is moved to
// its phone number in place.
const ACCOUNTS = [
  // The dev Platform Owner (create_dev_test_owner_account.mjs) keeps its
  // e-mail sign-in (the Platform Konsolu uses it) and is also an org admin.
  { key: "sahip", email: "sahip.test@abakus.dev", roles: ["admin"], branchAccess: [branchId], firstName: "Test", lastName: "Platform Sahibi" },
  // A POS device registered by the Müdür needs a second manager-tier account
  // to approve it (no self-approval): the Yönetici.
  { key: "yonetici", phone: "+905550000001", roles: ["admin"], branchAccess: [branchId], firstName: "Test", lastName: "Yönetici" },
  { key: "mudur", phone: "+905550000002", legacyEmail: "mudur.test@abakus.dev", roles: ["manager"], branchAccess: [branchId], firstName: "Test", lastName: "Müdür" },
  { key: "kasiyer", phone: "+905550000003", legacyEmail: "kasiyer.test@abakus.dev", roles: ["cashier"], branchAccess: [branchId], firstName: "Test", lastName: "Kasiyer" },
  { key: "dukkan-kurye", phone: "+905550000004", legacyEmail: "kurye.dukkan@abakus.dev", roles: ["courier"], branchAccess: [], firstName: "Dükkan", lastName: "Kuryesi" },
  { key: "dis-kurye-1", phone: "+905550000005", legacyEmail: "kurye.dis1@abakus.dev", roles: ["courier"], branchAccess: [], firstName: "Dış", lastName: "Kurye 1" },
  { key: "dis-kurye-2", phone: "+905550000006", legacyEmail: "kurye.dis2@abakus.dev", roles: ["courier"], branchAccess: [], firstName: "Dış", lastName: "Kurye 2" },
];

async function findUser(lookup) {
  try {
    return await lookup();
  } catch (error) {
    if (error.code === "auth/user-not-found") return null;
    throw error;
  }
}

/** Returns [user, generatedPassword | null]. */
async function ensureAccount(account) {
  const displayName = `${account.firstName} ${account.lastName}`;
  if (!account.phone) {
    const existing = await findUser(() => auth.getUserByEmail(account.email));
    if (existing) {
      console.log(`${TAG} ${account.email}: already exists (uid=${existing.uid}), password unchanged.`);
      return [existing, null];
    }
    const password = randomBytes(9).toString("base64url");
    const user = await auth.createUser({ email: account.email, password, displayName });
    console.log(`${TAG} ${account.email}: created (uid=${user.uid}).`);
    return [user, password];
  }

  const loginEmail = staffLoginEmailForPhone(account.phone);
  const byPhone = await findUser(() => auth.getUserByPhoneNumber(account.phone));
  if (byPhone) {
    if (byPhone.email !== loginEmail) await auth.updateUser(byPhone.uid, { email: loginEmail });
    console.log(`${TAG} ${account.phone}: already exists (uid=${byPhone.uid}), password unchanged.`);
    return [byPhone, null];
  }
  const legacy = account.legacyEmail ? await findUser(() => auth.getUserByEmail(account.legacyEmail)) : null;
  if (legacy) {
    const user = await auth.updateUser(legacy.uid, { phoneNumber: account.phone, email: loginEmail, displayName });
    console.log(`${TAG} ${account.legacyEmail} -> ${account.phone}: moved to phone sign-in (uid=${user.uid}), password unchanged.`);
    return [user, null];
  }
  const password = randomBytes(9).toString("base64url");
  const user = await auth.createUser({ phoneNumber: account.phone, email: loginEmail, password, displayName });
  console.log(`${TAG} ${account.phone}: created (uid=${user.uid}).`);
  return [user, password];
}

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
    const [user, password] = await ensureAccount(account);
    if (password) created.push({ login: account.phone ?? account.email, password });
    await db.collection("memberships").doc(`${organizationId}_${user.uid}`).set({
      organizationId,
      uid: user.uid,
      roles: account.roles,
      branchAccess: account.branchAccess,
      restaurantAccess: [],
      status: "active",
      version: 1,
      firstName: account.firstName,
      lastName: account.lastName,
      ...(account.phone ? { phoneNumber: account.phone } : {}),
    }, { merge: true });
  }

  if (created.length > 0) {
    console.log(`\n${TAG} NEW sign-ins (shown once — keep them safe):`);
    for (const c of created) console.log(`  ${c.login}  ${c.password}`);
  }
  console.log(`\n${TAG} done. Each account's claims sync on its first sign-in in the app.`);
  await app.delete();
}

main().catch((error) => {
  console.error(`${TAG} failed:`, error);
  process.exitCode = 1;
});
