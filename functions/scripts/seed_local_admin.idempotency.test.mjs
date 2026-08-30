// AP-3 wave 7 — proves `seed_local_admin.js`'s guest/sub-account seeding is
// genuinely idempotent (the real defect this test guards against: a prior
// version derived `guestSubAccounts`/`tableGuestSessions` document ids from
// a freshly-random anonymous-auth uid minted on every run, so rerunning the
// script left the previous run's guest documents orphaned instead of
// overwriting them — three guests would silently become six, nine, ...).
//
// Requires a running local emulator (Firestore + Auth at minimum) — same
// refusal discipline as the seed script itself: this test never touches
// anything but 127.0.0.1/localhost.
//
// Run from `functions/`:
//   FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 FIREBASE_AUTH_EMULATOR_HOST=127.0.0.1:9099 \
//     node --test scripts/seed_local_admin.idempotency.test.mjs
import test from "node:test";
import assert from "node:assert/strict";
import { createRequire } from "node:module";

const firestoreHost = process.env.FIRESTORE_EMULATOR_HOST || "";
const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST || "";
const isLocal = (h) => h.startsWith("127.0.0.1:") || h.startsWith("localhost:");
if (!isLocal(firestoreHost) || !isLocal(authHost)) {
  throw new Error(
    "FIRESTORE_EMULATOR_HOST/FIREBASE_AUTH_EMULATOR_HOST must both point at a local emulator to run this test.",
  );
}

const require = createRequire(import.meta.url);
const { main: seed } = require("./seed_local_admin.js");
const admin = require("firebase-admin");

const TABLE_SESSION_ID = "tsess-ap3vis";
const EXPECTED_SUB_ACCOUNT_IDS = [
  "subaccount-tsess-ap3vis-guest-ap3vis-ayse",
  "subaccount-tsess-ap3vis-guest-ap3vis-mehmet",
  "subaccount-tsess-ap3vis-guest-ap3vis-zeynep",
].sort();
const EXPECTED_SESSION_IDS = [
  "tgs-ap3vis-guest-ap3vis-ayse",
  "tgs-ap3vis-guest-ap3vis-mehmet",
  "tgs-ap3vis-guest-ap3vis-zeynep",
].sort();

async function snapshot(db) {
  const subAccounts = await db
    .collection("guestSubAccounts")
    .where("tableSessionId", "==", TABLE_SESSION_ID)
    .get();
  const sessions = await db
    .collection("tableGuestSessions")
    .where("tableSessionId", "==", TABLE_SESSION_ID)
    .get();
  return {
    subAccountIds: subAccounts.docs.map((d) => d.id).sort(),
    subAccountNames: subAccounts.docs.map((d) => d.data().displayName).sort(),
    sessionIds: sessions.docs.map((d) => d.id).sort(),
  };
}

test("seed_local_admin: guest sub-accounts are exactly 3, unchanged across three reruns", async () => {
  const db = admin.firestore();

  await seed();
  const afterRun1 = await snapshot(db);
  assert.deepEqual(afterRun1.subAccountIds, EXPECTED_SUB_ACCOUNT_IDS);
  assert.deepEqual(afterRun1.sessionIds, EXPECTED_SESSION_IDS);
  assert.deepEqual(
    afterRun1.subAccountNames,
    ["Ayşe", "Mehmet", "Zeynep"].sort(),
    "no duplicate/extra display names after the first run",
  );

  await seed();
  const afterRun2 = await snapshot(db);
  assert.deepEqual(afterRun2, afterRun1, "a second run must produce byte-identical ids/names — no growth");

  await seed();
  const afterRun3 = await snapshot(db);
  assert.deepEqual(afterRun3, afterRun1, "a third run must still produce byte-identical ids/names — no growth");
});
