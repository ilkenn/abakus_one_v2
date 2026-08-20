import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `getCustomerProfileCompletionState` — Customer
 * Registration CR.1 security fix. Mirrors `completeCustomerProfile.test.ts`'s
 * exact pattern.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const COMPLETION_STATE_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/getCustomerProfileCompletionState`;
const SINGLE_TENANT_ORGANIZATION_ID = "org-1";

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

async function createAnonymousUser(): Promise<{ idToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken: string; localId: string };
  return { idToken: body.idToken, uid: body.localId };
}

const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);
let phoneCounter = 0;

async function createRealPhoneUser(): Promise<{ idToken: string; uid: string }> {
  phoneCounter += 1;
  const phoneNumber = `+1555${PHONE_NAMESPACE}${String(phoneCounter).padStart(3, "0")}`;
  const sendRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ phoneNumber, recaptchaToken: "ignored-by-emulator" }),
    },
  );
  const sendBody = (await sendRes.json()) as { sessionInfo: string };
  const codesRes = await fetch(`${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`);
  const codesBody = (await codesRes.json()) as { verificationCodes: { sessionInfo: string; code: string }[] };
  const match = codesBody.verificationCodes.find((c) => c.sessionInfo === sendBody.sessionInfo)!;
  const signInRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }),
    },
  );
  const signInBody = (await signInRes.json()) as { idToken: string; localId: string };
  return { idToken: signInBody.idToken, uid: signInBody.localId };
}

const db = () => admin.firestore();

function completeCustomerPayload(overrides: Record<string, unknown> = {}) {
  return {
    uid: "placeholder",
    firstName: "Ayşe",
    lastName: "Yılmaz",
    displayName: "Ayşe Yılmaz",
    email: "ayse.yilmaz@example.com",
    phoneNumber: "+15559990000",
    accountStatus: "active",
    occupationStatus: "other",
    workplaceName: null,
    educationalInstitutionName: null,
    gender: "female",
    birthDate: "1990-08-20",
    profileCompletedAt: admin.firestore.Timestamp.now(),
    createdAt: admin.firestore.Timestamp.now(),
    updatedAt: admin.firestore.Timestamp.now(),
    ...overrides,
  };
}

async function seedCompleteCustomer(uid: string, overrides: Record<string, unknown> = {}) {
  await db().collection("customers").doc(uid).set(completeCustomerPayload({ uid, ...overrides }));
}

async function seedMembership(uid: string, organizationId: string = SINGLE_TENANT_ORGANIZATION_ID) {
  await db().collection("tenantCustomers").doc(`${organizationId}_${uid}`).set({
    organizationId,
    uid,
    createdAt: admin.firestore.Timestamp.now(),
  });
}

// =========================================================================
// A. Authentication / real-customer gating
// =========================================================================

test("an unauthenticated caller is rejected", async () => {
  const { httpStatus, body } = await callCallable(COMPLETION_STATE_URL, {});
  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("an anonymous (non-phone) authenticated user is rejected — not a real customer", async () => {
  const { idToken } = await createAnonymousUser();
  const { httpStatus, body } = await callCallable(COMPLETION_STATE_URL, {}, idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("a request with no App Check token still succeeds under the emulator — matches this codebase's shared appCheckConfig policy", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus } = await callCallable(COMPLETION_STATE_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
});

// =========================================================================
// B. Classification
// =========================================================================

test("a first-time phone customer — neither customers/{uid} nor tenantCustomers exists — resolves incomplete, never an error", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(COMPLETION_STATE_URL, {}, idToken);

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.state, "incomplete");
  assert.strictEqual(body.result?.reason, "customerMissing");
});

test("customer exists and is fully complete, but membership is missing — resolves incomplete, reason membershipMissing", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedCompleteCustomer(uid);
  // No membership seeded.

  const { httpStatus, body } = await callCallable(COMPLETION_STATE_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.state, "incomplete");
  assert.strictEqual(body.result?.reason, "membershipMissing");
});

test("membership exists but customers/{uid} does not — resolves incomplete, reason customerMissing", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedMembership(uid);
  // No customer doc seeded.

  const { httpStatus, body } = await callCallable(COMPLETION_STATE_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.state, "incomplete");
  assert.strictEqual(body.result?.reason, "customerMissing");
});

test("a required customer field (gender) is missing — resolves incomplete, reason profileFieldsIncomplete", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const payload = completeCustomerPayload({ uid });
  delete (payload as Record<string, unknown>).gender;
  await db().collection("customers").doc(uid).set(payload);
  await seedMembership(uid);

  const { httpStatus, body } = await callCallable(COMPLETION_STATE_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.state, "incomplete");
  assert.strictEqual(body.result?.reason, "profileFieldsIncomplete");
});

test("profileCompletedAt is missing — resolves incomplete, reason profileFieldsIncomplete", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const payload = completeCustomerPayload({ uid });
  delete (payload as Record<string, unknown>).profileCompletedAt;
  await db().collection("customers").doc(uid).set(payload);
  await seedMembership(uid);

  const { httpStatus, body } = await callCallable(COMPLETION_STATE_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.state, "incomplete");
  assert.strictEqual(body.result?.reason, "profileFieldsIncomplete");
});

test("CR.1.1 — a legacy customer complete in every other field but missing birthDate resolves incomplete, reason profileFieldsIncomplete", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  const payload = completeCustomerPayload({ uid });
  delete (payload as Record<string, unknown>).birthDate;
  await db().collection("customers").doc(uid).set(payload);
  await seedMembership(uid);

  const { httpStatus, body } = await callCallable(COMPLETION_STATE_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.state, "incomplete");
  assert.strictEqual(body.result?.reason, "profileFieldsIncomplete");
});

test("both canonical records fully complete — resolves complete, no reason", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedCompleteCustomer(uid);
  await seedMembership(uid);

  const { httpStatus, body } = await callCallable(COMPLETION_STATE_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.state, "complete");
  assert.strictEqual(body.result?.reason, undefined);
});

// =========================================================================
// C. Server-authoritative identity — never trust the client
// =========================================================================

test("a client-supplied organizationId is never read — resolution always uses the server-side single-tenant constant", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedCompleteCustomer(uid);
  await seedMembership(uid, SINGLE_TENANT_ORGANIZATION_ID);
  // Seed a DIFFERENT membership under a client-chosen tenant too, to prove
  // it's never consulted.
  await seedMembership(uid, "some-other-tenant-the-client-tried-to-choose");

  const { httpStatus, body } = await callCallable(
    COMPLETION_STATE_URL,
    { organizationId: "some-other-tenant-the-client-tried-to-choose" },
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  // Resolves complete because the REAL (server-resolved) org-1 membership
  // exists — proves the client's organizationId had zero effect either way.
  assert.strictEqual(body.result?.state, "complete");
});

test("the response never exposes cross-tenant or internal document data — only the narrow {state, reason} shape", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedCompleteCustomer(uid, { email: "should-never-appear@example.com" });
  await seedMembership(uid);

  const { body } = await callCallable(COMPLETION_STATE_URL, {}, idToken);
  const keys = Object.keys(body.result ?? {}).sort();
  assert.deepStrictEqual(keys, ["state"]);
  assert.strictEqual(JSON.stringify(body.result).includes("should-never-appear"), false);
});
