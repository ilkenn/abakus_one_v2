import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * ADR-085 (revised) — staff accounts created and managed from the panel;
 * staff sign in with phone number + password. Emulator-backed, same
 * wire-protocol pattern as `staffMembership.test.ts`.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const CREATE_URL = fn("createStaffAccount");
const SET_PASSWORD_URL = fn("setStaffPassword");
const UPDATE_URL = fn("updateStaffMember");
const DIRECTORY_URL = fn("listStaffMembersForOrganization");
const PASSWORD = "dogru-sifre-123";

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

async function refreshIdToken(refreshToken: string): Promise<{ status: number; idToken?: string }> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  const body = (await response.json()) as { id_token?: string };
  return { status: response.status, idToken: body.id_token };
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);
let phoneCounter = 0;
function nextPhone(): string {
  phoneCounter += 1;
  return `+1555${PHONE_NAMESPACE}${String(phoneCounter).padStart(3, "0")}`;
}
function loginEmail(phone: string): string {
  return `${phone.replace(/^\+/, "")}@staff-login.abakus.invalid`;
}

/** The customer path: the Auth emulator's real SMS flow. */
async function signInWithPhone(phoneNumber: string) {
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

/** The staff path: phone number + password, through the hidden sign-in e-mail. */
async function signInWithPassword(phone: string, password: string) {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ email: loginEmail(phone), password, returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken?: string; refreshToken?: string; localId?: string };
  return { status: response.status, idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function seedBranch(organizationId: string, restaurantId: string) {
  const branchId = nextId("branch");
  await admin.firestore().collection("branches").doc(branchId).set({
    restaurantId, organizationId, name: "Şube", status: "active", emergencyStopped: false,
  });
  return branchId;
}

async function seedTenant() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  await admin.firestore().collection("organizations").doc(organizationId).set({ name: "Test Org", isActive: true });
  await admin.firestore().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test Restaurant", isActive: true });
  const branchId = await seedBranch(organizationId, restaurantId);
  return { organizationId, restaurantId, branchId };
}

async function freshToken(refreshToken: string): Promise<string> {
  const refreshed = await refreshIdToken(refreshToken);
  assert.strictEqual(refreshed.status, 200, "token refresh must succeed");
  return refreshed.idToken!;
}

/** A phone-signed-in first admin of a fresh organization, via the real callables. */
async function bootstrapAdmin(organizationId: string) {
  const phone = nextPhone();
  const { idToken, refreshToken, uid } = await signInWithPhone(phone);
  const bootstrap = await callCallable(BOOTSTRAP_URL, { organizationId }, idToken);
  assert.strictEqual(bootstrap.httpStatus, 200, JSON.stringify(bootstrap.body));
  await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  return { uid, phone, idToken: await freshToken(refreshToken) };
}

/** A phone-signed-in member seeded directly with [roles], claims synced. */
async function seededMember(organizationId: string, roles: string[], branchAccess: string[] = []) {
  const phone = nextPhone();
  const { idToken, refreshToken, uid } = await signInWithPhone(phone);
  await admin.firestore().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles, branchAccess, restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(), version: 1,
  });
  await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  return { uid, phone, idToken: await freshToken(refreshToken) };
}

function claimsOf(idToken: string): Record<string, unknown> {
  return JSON.parse(Buffer.from(idToken.split(".")[1], "base64").toString("utf8"));
}

function createInput(organizationId: string, overrides: Record<string, unknown> = {}) {
  return {
    organizationId,
    firstName: "Ayşe",
    lastName: "Yılmaz",
    phoneNumber: nextPhone(),
    password: PASSWORD,
    roles: ["cashier"],
    branchAccess: [],
    ...overrides,
  };
}

test("createStaffAccount: the account is active at once and signs in with phone + password; the directory shows the name", async () => {
  const { organizationId, branchId } = await seedTenant();
  const adminCaller = await bootstrapAdmin(organizationId);
  const input = createInput(organizationId, { branchAccess: [branchId] });

  const created = await callCallable(CREATE_URL, input, adminCaller.idToken);
  assert.strictEqual(created.httpStatus, 200, JSON.stringify(created.body));
  assert.strictEqual(created.body.result?.reusedExistingAccount, false);

  const signIn = await signInWithPassword(input.phoneNumber as string, PASSWORD);
  assert.strictEqual(signIn.status, 200);
  assert.strictEqual(signIn.uid, created.body.result?.uid);
  await callCallable(SYNC_CLAIMS_URL, {}, signIn.idToken);
  const claims = claimsOf(await freshToken(signIn.refreshToken!));
  assert.deepStrictEqual(claims.roles, { [organizationId]: ["cashier"] });

  const directory = await callCallable(DIRECTORY_URL, { organizationId }, adminCaller.idToken);
  const entry = (directory.body.result?.members as Record<string, unknown>[]).find((m) => m.uid === signIn.uid);
  assert.strictEqual(entry?.firstName, "Ayşe");
  assert.strictEqual(entry?.phoneNumber, input.phoneNumber);

  const audit = await admin.firestore().collection("auditEvents")
    .where("targetRef", "==", `memberships/${organizationId}_${signIn.uid}`).get();
  assert.strictEqual(audit.docs[0]?.data().type, "staff.accountCreated");
  assert.ok(!JSON.stringify(audit.docs[0]?.data()).includes(PASSWORD), "the password must never reach the audit log");
});

test("createStaffAccount: an existing customer keeps the same account — SMS and password reach one uid", async () => {
  const { organizationId } = await seedTenant();
  const adminCaller = await bootstrapAdmin(organizationId);
  const phone = nextPhone();
  const customer = await signInWithPhone(phone);

  const created = await callCallable(CREATE_URL, createInput(organizationId, { phoneNumber: phone, roles: ["courier"] }), adminCaller.idToken);
  assert.strictEqual(created.httpStatus, 200, JSON.stringify(created.body));
  assert.strictEqual(created.body.result?.uid, customer.uid);
  assert.strictEqual(created.body.result?.reusedExistingAccount, true);

  const byPassword = await signInWithPassword(phone, PASSWORD);
  assert.strictEqual(byPassword.uid, customer.uid);
  const bySms = await signInWithPhone(phone);
  assert.strictEqual(bySms.uid, customer.uid);
});

test("createStaffAccount: refuses a number that is already staff here, the caller's own number, and bad input", async () => {
  const { organizationId } = await seedTenant();
  const adminCaller = await bootstrapAdmin(organizationId);
  const input = createInput(organizationId);
  assert.strictEqual((await callCallable(CREATE_URL, input, adminCaller.idToken)).httpStatus, 200);

  const duplicate = await callCallable(CREATE_URL, { ...input, password: "baska-sifre-456" }, adminCaller.idToken);
  assert.strictEqual(duplicate.body.error?.status, "ALREADY_EXISTS", JSON.stringify(duplicate.body));
  const self = await callCallable(CREATE_URL, createInput(organizationId, { phoneNumber: adminCaller.phone }), adminCaller.idToken);
  assert.strictEqual(self.httpStatus, 403, JSON.stringify(self.body));

  for (const overrides of [{ password: "kisa" }, { phoneNumber: "05551234567" }, { firstName: " " }, { roles: [] }, { roles: ["superuser"] }]) {
    const result = await callCallable(CREATE_URL, createInput(organizationId, overrides), adminCaller.idToken);
    assert.strictEqual(result.httpStatus, 400, `${JSON.stringify(overrides)} -> ${JSON.stringify(result.body)}`);
  }
});

test("createStaffAccount: a manager adds cashier/courier-level staff only, only in their own branches", async () => {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const otherBranchId = await seedBranch(organizationId, restaurantId);
  await bootstrapAdmin(organizationId);
  const manager = await seededMember(organizationId, ["manager"], [branchId]);

  const ok = await callCallable(CREATE_URL, createInput(organizationId, { roles: ["courier"], branchAccess: [branchId] }), manager.idToken);
  assert.strictEqual(ok.httpStatus, 200, JSON.stringify(ok.body));

  for (const overrides of [
    { roles: ["manager"], branchAccess: [branchId] },
    { roles: ["admin"], branchAccess: [branchId] },
    { roles: ["courier"], branchAccess: [otherBranchId] },
    { roles: ["courier"], branchAccess: [] },
  ]) {
    const result = await callCallable(CREATE_URL, createInput(organizationId, overrides), manager.idToken);
    assert.strictEqual(result.httpStatus, 403, `${JSON.stringify(overrides)} -> ${JSON.stringify(result.body)}`);
  }

  const cashier = await seededMember(organizationId, ["cashier"], [branchId]);
  const byCashier = await callCallable(CREATE_URL, createInput(organizationId, { roles: ["courier"], branchAccess: [branchId] }), cashier.idToken);
  assert.strictEqual(byCashier.httpStatus, 403, JSON.stringify(byCashier.body));
});

test("setStaffPassword: the new password works, the old one does not, and open sessions end", async () => {
  const { organizationId, branchId } = await seedTenant();
  const adminCaller = await bootstrapAdmin(organizationId);
  const input = createInput(organizationId, { branchAccess: [branchId] });
  const created = await callCallable(CREATE_URL, input, adminCaller.idToken);
  const staffUid = created.body.result?.uid as string;
  const beforeSet = Math.floor(Date.now() / 1000) * 1000;

  const set = await callCallable(SET_PASSWORD_URL, { organizationId, targetUid: staffUid, password: "yeni-sifre-789" }, adminCaller.idToken);
  assert.strictEqual(set.httpStatus, 200, JSON.stringify(set.body));

  assert.strictEqual((await signInWithPassword(input.phoneNumber as string, PASSWORD)).status, 400);
  assert.strictEqual((await signInWithPassword(input.phoneNumber as string, "yeni-sifre-789")).status, 200);
  // Open sessions end: refresh tokens are revoked. The Auth emulator records
  // the revocation (`tokensValidAfterTime`) but, unlike the real service,
  // still honours an old refresh token, so the record is what is asserted.
  const validAfter = Date.parse((await admin.auth().getUser(staffUid)).tokensValidAfterTime ?? "");
  assert.ok(validAfter >= beforeSet, "refresh tokens must be revoked");
  const revocation = await admin.firestore().collection("authClaimsRevocations").doc(staffUid).get();
  assert.ok(revocation.exists, "staff claims must be stamped stale");
});

test("setStaffPassword: managers only their own branch's lower roles; nobody touches an admin's or their own", async () => {
  const { organizationId, branchId } = await seedTenant();
  const adminCaller = await bootstrapAdmin(organizationId);
  const otherAdmin = await seededMember(organizationId, ["admin"], [branchId]);
  const manager = await seededMember(organizationId, ["manager"], [branchId]);
  const otherManager = await seededMember(organizationId, ["manager"], [branchId]);
  const courier = await seededMember(organizationId, ["courier"], [branchId]);
  const newPassword = { password: "yeni-sifre-789" };

  const cases: [string, string, number][] = [
    [manager.idToken, courier.uid, 200],
    [manager.idToken, otherManager.uid, 403],
    [manager.idToken, adminCaller.uid, 403],
    [adminCaller.idToken, manager.uid, 200],
    [adminCaller.idToken, otherAdmin.uid, 403],
    [adminCaller.idToken, adminCaller.uid, 403],
  ];
  for (const [caller, targetUid, expected] of cases) {
    const result = await callCallable(SET_PASSWORD_URL, { organizationId, targetUid, ...newPassword }, caller);
    assert.strictEqual(result.httpStatus, expected, `${targetUid} -> ${JSON.stringify(result.body)}`);
  }
});

test("updateStaffMember: a manager suspends their courier (access ends at once) but cannot promote anyone to manager", async () => {
  const { organizationId, branchId } = await seedTenant();
  await bootstrapAdmin(organizationId);
  const manager = await seededMember(organizationId, ["manager"], [branchId]);
  const courier = await seededMember(organizationId, ["courier"], [branchId]);

  const promote = await callCallable(UPDATE_URL, { organizationId, targetUid: courier.uid, roles: ["manager"] }, manager.idToken);
  assert.strictEqual(promote.httpStatus, 403, JSON.stringify(promote.body));

  const suspend = await callCallable(UPDATE_URL, { organizationId, targetUid: courier.uid, status: "suspended" }, manager.idToken);
  assert.strictEqual(suspend.httpStatus, 200, JSON.stringify(suspend.body));
  const user = await admin.auth().getUser(courier.uid);
  assert.deepStrictEqual(user.customClaims?.roles, {});
  const revocation = await admin.firestore().collection("authClaimsRevocations").doc(courier.uid).get();
  assert.ok(revocation.exists, "suspension must stamp the staff claims stale");

  const reactivate = await callCallable(UPDATE_URL, { organizationId, targetUid: courier.uid, status: "active", roles: ["cashier", "courier"] }, manager.idToken);
  assert.strictEqual(reactivate.httpStatus, 200, JSON.stringify(reactivate.body));
  const membership = await admin.firestore().collection("memberships").doc(`${organizationId}_${courier.uid}`).get();
  assert.deepStrictEqual(membership.data()?.roles, ["cashier", "courier"]);
  assert.strictEqual(membership.data()?.status, "active");
});

test("updateStaffMember: an admin changes a manager's roles but never another admin's, nor grants the owner role", async () => {
  const { organizationId, branchId } = await seedTenant();
  const adminCaller = await bootstrapAdmin(organizationId);
  const otherAdmin = await seededMember(organizationId, ["admin"], [branchId]);
  const manager = await seededMember(organizationId, ["manager"], [branchId]);

  const ok = await callCallable(UPDATE_URL, { organizationId, targetUid: manager.uid, roles: ["manager", "cashier"] }, adminCaller.idToken);
  assert.strictEqual(ok.httpStatus, 200, JSON.stringify(ok.body));
  const touchAdmin = await callCallable(UPDATE_URL, { organizationId, targetUid: otherAdmin.uid, status: "suspended" }, adminCaller.idToken);
  assert.strictEqual(touchAdmin.httpStatus, 403, JSON.stringify(touchAdmin.body));
  const owner = await callCallable(UPDATE_URL, { organizationId, targetUid: manager.uid, roles: ["tenantOwner"] }, adminCaller.idToken);
  assert.strictEqual(owner.httpStatus, 403, JSON.stringify(owner.body));
});
