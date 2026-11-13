import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * ADR-085 phase A — staff invited by phone number. Emulator-backed, same
 * wire-protocol pattern as `staffMembership.test.ts`: raw HTTP against the
 * callables, real Auth-emulator phone sign-ins (so the ID token carries a
 * real `phone_number` claim), real Firestore fixtures.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const INVITE_URL = fn("inviteStaffByPhone");
const REVOKE_INVITE_URL = fn("revokeStaffInvite");
const LIST_INVITES_URL = fn("listStaffInvites");

let app: admin.app.App;

before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});

after(async () => {
  await app.delete();
});

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as {
    result?: Record<string, unknown>;
    error?: { status?: string; message?: string };
  };
  return { httpStatus: response.status, body };
}

async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  const body = (await response.json()) as { id_token: string };
  assert.strictEqual(response.status, 200, "Auth emulator token refresh must succeed");
  return body.id_token;
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);
let phoneCounter = 0;
function nextPhone(): string {
  phoneCounter += 1;
  return `+1555${PHONE_NAMESPACE}${String(phoneCounter).padStart(3, "0")}`;
}

/** Signs [phoneNumber] in through the Auth emulator's real SMS flow. */
async function signInWithPhone(phoneNumber: string): Promise<{ idToken: string; refreshToken: string; uid: string }> {
  const sendRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ phoneNumber, recaptchaToken: "ignored-by-emulator" }) },
  );
  const sendBody = (await sendRes.json()) as { sessionInfo: string };
  const codesRes = await fetch(`${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`);
  const codesBody = (await codesRes.json()) as { verificationCodes: { sessionInfo: string; code: string }[] };
  const match = codesBody.verificationCodes.find((c) => c.sessionInfo === sendBody.sessionInfo)!;
  const signInRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }) },
  );
  const body = (await signInRes.json()) as { idToken: string; refreshToken: string; localId: string };
  assert.strictEqual(signInRes.status, 200, "Auth emulator phone sign-in must succeed");
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function seedTenant() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const db = admin.firestore();
  await db.collection("organizations").doc(organizationId).set({ name: "Test Org", isActive: true });
  await db.collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test Restaurant", isActive: true });
  await db.collection("branches").doc(branchId).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
  });
  return { organizationId, restaurantId, branchId };
}

/** A phone-signed-in first admin of a fresh organization, via the real callables. */
async function bootstrapPhoneAdmin(organizationId: string) {
  const phone = nextPhone();
  const { idToken, refreshToken, uid } = await signInWithPhone(phone);
  const bootstrap = await callCallable(BOOTSTRAP_URL, { organizationId }, idToken);
  assert.strictEqual(bootstrap.httpStatus, 200, JSON.stringify(bootstrap.body));
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  return { uid, phone, idToken: await refreshIdToken(refreshToken) };
}

/** A phone-signed-in member seeded directly with [roles], claims synced. */
async function seededPhoneMember(organizationId: string, roles: string[], branchAccess: string[] = []) {
  const phone = nextPhone();
  const { idToken, refreshToken, uid } = await signInWithPhone(phone);
  await admin.firestore().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles, branchAccess, restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(), version: 1,
  });
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  return { uid, phone, idToken: await refreshIdToken(refreshToken) };
}

function decodeIdTokenClaims(idToken: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(idToken.split(".")[1], "base64").toString("utf8"));
}

test("inviteStaffByPhone: a pending invite binds on that number's first SMS sign-in, and the same sync carries the roles", async () => {
  const { organizationId, branchId } = await seedTenant();
  const adminCaller = await bootstrapPhoneAdmin(organizationId);
  const phone = nextPhone();

  const invite = await callCallable(INVITE_URL, { organizationId, phoneNumber: phone, roles: ["courier"], branchAccess: [branchId] }, adminCaller.idToken);
  assert.strictEqual(invite.httpStatus, 200, JSON.stringify(invite.body));
  assert.strictEqual(invite.body.result?.status, "pending");

  const staff = await signInWithPhone(phone);
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, staff.idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  assert.strictEqual(sync.body.result?.claimedInvites, 1);

  const claims = decodeIdTokenClaims(await refreshIdToken(staff.refreshToken));
  assert.deepStrictEqual(claims.roles, { [organizationId]: ["courier"] });
  assert.deepStrictEqual(claims.branchAccess, { [organizationId]: [branchId] });

  const inviteDoc = await admin.firestore().collection("staffInvites").doc(`${organizationId}_${phone}`).get();
  assert.strictEqual(inviteDoc.data()?.status, "claimed");
  assert.strictEqual(inviteDoc.data()?.claimedByUid, staff.uid);

  // A second sync never re-applies a claimed invite.
  const again = await callCallable(SYNC_CLAIMS_URL, {}, staff.idToken);
  assert.strictEqual(again.body.result?.claimedInvites, 0);
});

test("inviteStaffByPhone: an existing account with that number is bound immediately", async () => {
  const { organizationId } = await seedTenant();
  const adminCaller = await bootstrapPhoneAdmin(organizationId);
  const phone = nextPhone();
  const existing = await signInWithPhone(phone);

  const invite = await callCallable(INVITE_URL, { organizationId, phoneNumber: phone, roles: ["cashier"] }, adminCaller.idToken);
  assert.strictEqual(invite.httpStatus, 200, JSON.stringify(invite.body));
  assert.strictEqual(invite.body.result?.status, "claimed");

  const membership = await admin.firestore().collection("memberships").doc(`${organizationId}_${existing.uid}`).get();
  assert.deepStrictEqual(membership.data()?.roles, ["cashier"]);
  assert.strictEqual(membership.data()?.status, "active");
  const claims = decodeIdTokenClaims(await refreshIdToken(existing.refreshToken));
  assert.deepStrictEqual(claims.roles, { [organizationId]: ["cashier"] });
});

test("inviteStaffByPhone: an existing membership keeps its status and gains the invited roles", async () => {
  const { organizationId } = await seedTenant();
  const adminCaller = await bootstrapPhoneAdmin(organizationId);
  const member = await seededPhoneMember(organizationId, ["cashier"]);

  const invite = await callCallable(INVITE_URL, { organizationId, phoneNumber: member.phone, roles: ["courier"] }, adminCaller.idToken);
  assert.strictEqual(invite.httpStatus, 200, JSON.stringify(invite.body));

  const membership = await admin.firestore().collection("memberships").doc(`${organizationId}_${member.uid}`).get();
  assert.deepStrictEqual([...membership.data()?.roles].sort(), ["cashier", "courier"]);
  assert.strictEqual(membership.data()?.version, 2);
});

test("inviteStaffByPhone: nobody can invite their own phone number", async () => {
  const { organizationId } = await seedTenant();
  const adminCaller = await bootstrapPhoneAdmin(organizationId);

  const invite = await callCallable(INVITE_URL, { organizationId, phoneNumber: adminCaller.phone, roles: ["courier"] }, adminCaller.idToken);
  assert.strictEqual(invite.httpStatus, 403, JSON.stringify(invite.body));
  const inviteDoc = await admin.firestore().collection("staffInvites").doc(`${organizationId}_${adminCaller.phone}`).get();
  assert.strictEqual(inviteDoc.exists, false);
});

test("inviteStaffByPhone: a manager cannot invite (manageStaffAccounts is admin-only) and a non-member is refused", async () => {
  const { organizationId, branchId } = await seedTenant();
  await bootstrapPhoneAdmin(organizationId);
  const manager = await seededPhoneMember(organizationId, ["manager"], [branchId]);
  const outsider = await signInWithPhone(nextPhone());

  const byManager = await callCallable(INVITE_URL, { organizationId, phoneNumber: nextPhone(), roles: ["courier"] }, manager.idToken);
  assert.strictEqual(byManager.httpStatus, 403, JSON.stringify(byManager.body));
  const byOutsider = await callCallable(INVITE_URL, { organizationId, phoneNumber: nextPhone(), roles: ["courier"] }, outsider.idToken);
  assert.strictEqual(byOutsider.httpStatus, 403, JSON.stringify(byOutsider.body));
});

test("inviteStaffByPhone: rejects a malformed number, an empty or unknown role, and a branch of another organization", async () => {
  const { organizationId } = await seedTenant();
  const other = await seedTenant();
  const adminCaller = await bootstrapPhoneAdmin(organizationId);

  const cases: Record<string, unknown>[] = [
    { organizationId, phoneNumber: "05551234567", roles: ["courier"] },
    { organizationId, phoneNumber: nextPhone(), roles: [] },
    { organizationId, phoneNumber: nextPhone(), roles: ["superuser"] },
    { organizationId, phoneNumber: nextPhone(), roles: ["courier"], branchAccess: [other.branchId] },
  ];
  for (const data of cases) {
    const result = await callCallable(INVITE_URL, data, adminCaller.idToken);
    assert.strictEqual(result.httpStatus, 400, `${JSON.stringify(data)} -> ${JSON.stringify(result.body)}`);
  }
});

test("revokeStaffInvite: a revoked invite never binds, and listStaffInvites shows only pending ones", async () => {
  const { organizationId } = await seedTenant();
  const adminCaller = await bootstrapPhoneAdmin(organizationId);
  const revokedPhone = nextPhone();
  const pendingPhone = nextPhone();

  for (const phoneNumber of [revokedPhone, pendingPhone]) {
    const invite = await callCallable(INVITE_URL, { organizationId, phoneNumber, roles: ["courier"] }, adminCaller.idToken);
    assert.strictEqual(invite.httpStatus, 200, JSON.stringify(invite.body));
  }
  const revoke = await callCallable(REVOKE_INVITE_URL, { organizationId, phoneNumber: revokedPhone }, adminCaller.idToken);
  assert.strictEqual(revoke.body.result?.revoked, true);

  const list = await callCallable(LIST_INVITES_URL, { organizationId }, adminCaller.idToken);
  assert.strictEqual(list.httpStatus, 200, JSON.stringify(list.body));
  const phones = (list.body.result?.invites as { phoneNumber: string }[]).map((i) => i.phoneNumber);
  assert.deepStrictEqual(phones, [pendingPhone]);

  const staff = await signInWithPhone(revokedPhone);
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, staff.idToken);
  assert.strictEqual(sync.body.result?.claimedInvites, 0);
  const claims = decodeIdTokenClaims(await refreshIdToken(staff.refreshToken));
  assert.deepStrictEqual(claims.roles, {});
});
