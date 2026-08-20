import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `requestCustomerPhotoUploadGrant` — Profile
 * P.4.2A. Mirrors `submitDeliveryOrder.test.ts`'s exact pattern (raw HTTP
 * against the callable-functions wire protocol, real Firestore fixtures
 * seeded directly via the Admin SDK, real phone-auth via the Auth
 * emulator for the isRealCustomer check).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const GRANT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/requestCustomerPhotoUploadGrant`;

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

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
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

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

const db = () => admin.firestore();

async function seedTenantCustomer(organizationId: string, uid: string) {
  await db().collection("tenantCustomers").doc(`${organizationId}_${uid}`).set({ organizationId, uid });
}

async function seedEligiblePhoto(
  organizationId: string,
  uid: string,
  status: "pendingReview" | "underReview" | "approved" = "approved",
) {
  await db().collection("customerPhotos").doc(nextId("photo")).set({
    customerId: uid,
    organizationId,
    photoRef: `tenants/${organizationId}/customerPhotos/${uid}/${nextId("ref")}`,
    status,
    isSelectedAsProfilePhoto: false,
    uploadedAt: admin.firestore.Timestamp.now(),
    revision: 1,
  });
}

async function seedIneligiblePhoto(
  organizationId: string,
  uid: string,
  status: "rejected" | "removed",
) {
  await db().collection("customerPhotos").doc(nextId("photo")).set({
    customerId: uid,
    organizationId,
    photoRef: `tenants/${organizationId}/customerPhotos/${uid}/${nextId("ref")}`,
    status,
    isSelectedAsProfilePhoto: false,
    uploadedAt: admin.firestore.Timestamp.now(),
    revision: 1,
  });
}

async function seedExpiredGrant(organizationId: string, uid: string) {
  const grantId = nextId("stale-grant");
  await db().collection("customerPhotoUploadGrants").doc(grantId).set({
    uid,
    organizationId,
    objectPath: `tenants/${organizationId}/customerPhotos/${uid}/${grantId}`,
    contentType: "image/png",
    status: "issued",
    createdAt: admin.firestore.Timestamp.fromMillis(Date.now() - 20 * 60 * 1000),
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 60 * 1000), // already expired
  });
  return grantId;
}

function validRequest(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    organizationId: "org-1",
    contentType: "image/png",
    ...overrides,
  };
}

// =========================================================================
// A. Authentication / real-customer gating
// =========================================================================

test("a guest (unauthenticated caller) is rejected", async () => {
  const { httpStatus, body } = await callCallable(GRANT_URL, validRequest());
  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("an anonymous (non-phone) authenticated user is rejected — not a real customer", async () => {
  const { idToken } = await createAnonymousUser();
  const { httpStatus, body } = await callCallable(GRANT_URL, validRequest(), idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

// =========================================================================
// B. Tenant membership — never trust client-supplied organizationId
// =========================================================================

test("a valid same-tenant customer receives exactly one grant, bound to their own uid", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);

  const { httpStatus, body } = await callCallable(GRANT_URL, validRequest({ organizationId }), idToken);

  assert.strictEqual(httpStatus, 200);
  const grantId = body.result?.grantId as string;
  assert.ok(grantId, "grantId returned");
  assert.strictEqual(body.result?.objectPath, `tenants/${organizationId}/customerPhotos/${uid}/${grantId}`);

  const grantDoc = await db().collection("customerPhotoUploadGrants").doc(grantId).get();
  assert.ok(grantDoc.exists);
  assert.strictEqual(grantDoc.data()!.uid, uid);
  assert.strictEqual(grantDoc.data()!.organizationId, organizationId);
  assert.strictEqual(grantDoc.data()!.status, "issued");
});

test("a customer with no tenantCustomers record for the requested organization is rejected — cross-tenant request", async () => {
  const organizationId = nextId("org");
  const otherOrganizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  // Only a member of a DIFFERENT organization, not the requested one.
  await seedTenantCustomer(otherOrganizationId, uid);

  const { httpStatus, body } = await callCallable(GRANT_URL, validRequest({ organizationId }), idToken);

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("a customer with no tenantCustomers record at all is rejected", async () => {
  const organizationId = nextId("org");
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(GRANT_URL, validRequest({ organizationId }), idToken);

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("missing organizationId is rejected as invalid-argument, not silently defaulted", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(
    GRANT_URL,
    { contentType: "image/png" },
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("a non-image contentType is rejected as invalid-argument", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);

  const { httpStatus, body } = await callCallable(
    GRANT_URL,
    validRequest({ organizationId, contentType: "application/pdf" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

// =========================================================================
// C. Quota — max 10 including outstanding reservations
// =========================================================================

test("max 10: a customer with 9 eligible photos can still request 1 more grant", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  for (let i = 0; i < 9; i += 1) {
    await seedEligiblePhoto(organizationId, uid);
  }

  const { httpStatus } = await callCallable(GRANT_URL, validRequest({ organizationId }), idToken);
  assert.strictEqual(httpStatus, 200);
});

test("max 10: a customer with 10 eligible photos is rejected — resource-exhausted", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  for (let i = 0; i < 10; i += 1) {
    await seedEligiblePhoto(organizationId, uid);
  }

  const { httpStatus, body } = await callCallable(GRANT_URL, validRequest({ organizationId }), idToken);
  assert.strictEqual(httpStatus, 429);
  assert.strictEqual(body.error?.status, "RESOURCE_EXHAUSTED");
});

test("rejected/removed photos never count toward the limit — 10 rejected + 10 removed still allows a grant", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  for (let i = 0; i < 10; i += 1) {
    await seedIneligiblePhoto(organizationId, uid, "rejected");
  }
  for (let i = 0; i < 10; i += 1) {
    await seedIneligiblePhoto(organizationId, uid, "removed");
  }

  const { httpStatus } = await callCallable(GRANT_URL, validRequest({ organizationId }), idToken);
  assert.strictEqual(httpStatus, 200);
});

test("outstanding upload grants count toward the limit — 10 active grants block the 11th, before any real photo exists", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);

  for (let i = 0; i < 10; i += 1) {
    const { httpStatus } = await callCallable(
      GRANT_URL,
      validRequest({ organizationId, requestKey: nextId("key") }),
      idToken,
    );
    assert.strictEqual(httpStatus, 200, `grant ${i + 1} should succeed`);
  }

  const { httpStatus, body } = await callCallable(
    GRANT_URL,
    validRequest({ organizationId, requestKey: nextId("key") }),
    idToken,
  );
  assert.strictEqual(httpStatus, 429);
  assert.strictEqual(body.error?.status, "RESOURCE_EXHAUSTED");
});

test("a mix of eligible photos and active grants totalling 10 blocks the next request", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  for (let i = 0; i < 6; i += 1) {
    await seedEligiblePhoto(organizationId, uid);
  }
  for (let i = 0; i < 4; i += 1) {
    const { httpStatus } = await callCallable(
      GRANT_URL,
      validRequest({ organizationId, requestKey: nextId("key") }),
      idToken,
    );
    assert.strictEqual(httpStatus, 200);
  }

  const { httpStatus, body } = await callCallable(
    GRANT_URL,
    validRequest({ organizationId, requestKey: nextId("key") }),
    idToken,
  );
  assert.strictEqual(httpStatus, 429);
  assert.strictEqual(body.error?.status, "RESOURCE_EXHAUSTED");
});

test("expired reservations release capacity — a stale expired grant does not block a 10th real slot", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  await seedExpiredGrant(organizationId, uid); // would-be 1 of 10 if it still counted
  for (let i = 0; i < 9; i += 1) {
    await seedEligiblePhoto(organizationId, uid);
  }

  // 9 eligible + 1 EXPIRED grant (excluded) = 9 counted -> a 10th is allowed.
  const { httpStatus } = await callCallable(GRANT_URL, validRequest({ organizationId }), idToken);
  assert.strictEqual(httpStatus, 200);
});

// =========================================================================
// D. Concurrency safety
// =========================================================================

test("concurrent grant requests for the same customer never let outstanding+eligible slots exceed 10", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  for (let i = 0; i < 8; i += 1) {
    await seedEligiblePhoto(organizationId, uid); // 8 already used — only 2 slots free.
  }

  const results = await Promise.all(
    Array.from({ length: 6 }, () =>
      callCallable(GRANT_URL, validRequest({ organizationId, requestKey: nextId("key") }), idToken),
    ),
  );

  const successCount = results.filter((r) => r.httpStatus === 200).length;
  const exhaustedCount = results.filter((r) => r.body.error?.status === "RESOURCE_EXHAUSTED").length;
  assert.strictEqual(successCount, 2, `expected exactly 2 of 6 concurrent requests to succeed (2 free slots), got ${successCount}`);
  assert.strictEqual(successCount + exhaustedCount, 6);

  const grantsSnap = await db()
    .collection("customerPhotoUploadGrants")
    .where("uid", "==", uid)
    .where("status", "==", "issued")
    .get();
  assert.strictEqual(grantsSnap.size, 2, "never more than the 2 actually-available slots were reserved");
});

// =========================================================================
// E. Idempotency / retry
// =========================================================================

test("retrying with the same requestKey and the same parameters reuses the exact same grant — does not consume a second slot", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  const requestKey = nextId("key");

  const first = await callCallable(GRANT_URL, validRequest({ organizationId, requestKey }), idToken);
  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(first.body.result?.reused, false);

  const second = await callCallable(GRANT_URL, validRequest({ organizationId, requestKey }), idToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.reused, true);
  assert.strictEqual(second.body.result?.grantId, first.body.result?.grantId);
  assert.strictEqual(second.body.result?.objectPath, first.body.result?.objectPath);

  const grantsSnap = await db()
    .collection("customerPhotoUploadGrants")
    .where("uid", "==", uid)
    .where("status", "==", "issued")
    .get();
  assert.strictEqual(grantsSnap.size, 1, "a retried request never mints a second reservation");
});

test("reusing the same requestKey with DIFFERENT parameters is rejected — failed-precondition, not silently honored", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  const requestKey = nextId("key");

  const first = await callCallable(
    GRANT_URL,
    validRequest({ organizationId, requestKey, contentType: "image/png" }),
    idToken,
  );
  assert.strictEqual(first.httpStatus, 200);

  const second = await callCallable(
    GRANT_URL,
    validRequest({ organizationId, requestKey, contentType: "image/jpeg" }),
    idToken,
  );
  assert.strictEqual(second.httpStatus, 400);
  assert.strictEqual(second.body.error?.status, "FAILED_PRECONDITION");
});

test("no requestKey given: two calls each mint a distinct, non-idempotent grant", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);

  const first = await callCallable(GRANT_URL, validRequest({ organizationId }), idToken);
  const second = await callCallable(GRANT_URL, validRequest({ organizationId }), idToken);

  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(second.httpStatus, 200);
  assert.notStrictEqual(first.body.result?.grantId, second.body.result?.grantId);
});

test("a retry after the original grant EXPIRED reissues a fresh grant over the same requestKey rather than treating it as a conflict", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  const requestKey = nextId("key");

  const first = await callCallable(GRANT_URL, validRequest({ organizationId, requestKey }), idToken);
  assert.strictEqual(first.httpStatus, 200);
  const grantId = first.body.result?.grantId as string;

  // Simulate expiry by rewriting the same document's expiresAt into the
  // past directly (Admin SDK — bypasses nothing relevant here, this is
  // just fast-forwarding time for the test).
  await db().collection("customerPhotoUploadGrants").doc(grantId).update({
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000),
  });

  const second = await callCallable(GRANT_URL, validRequest({ organizationId, requestKey }), idToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.reused, false);
  assert.strictEqual(second.body.result?.grantId, grantId, "reissues over the same deterministic id/path");

  const reissued = await db().collection("customerPhotoUploadGrants").doc(grantId).get();
  assert.ok((reissued.data()!.expiresAt as admin.firestore.Timestamp).toMillis() > Date.now());
});

// =========================================================================
// F. CR.1.2 — upload-intent (purpose)
// =========================================================================

test("a normal request with no purpose stores purpose: null on the grant — existing flow unaffected", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);

  const { httpStatus, body } = await callCallable(GRANT_URL, validRequest({ organizationId }), idToken);
  assert.strictEqual(httpStatus, 200);

  const grantId = body.result?.grantId as string;
  const grantDoc = await db().collection("customerPhotoUploadGrants").doc(grantId).get();
  assert.strictEqual(grantDoc.data()!.purpose, null);
});

test('purpose: "profileOnboarding" is accepted and stored server-authoritatively on the grant', async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);

  const { httpStatus, body } = await callCallable(
    GRANT_URL,
    validRequest({ organizationId, purpose: "profileOnboarding" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);

  const grantId = body.result?.grantId as string;
  const grantDoc = await db().collection("customerPhotoUploadGrants").doc(grantId).get();
  assert.strictEqual(grantDoc.data()!.purpose, "profileOnboarding");
});

test("an arbitrary/invalid purpose is rejected as invalid-argument — no open-ended purposes accepted", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);

  const { httpStatus, body } = await callCallable(
    GRANT_URL,
    validRequest({ organizationId, purpose: "somethingElse" }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("reusing the same requestKey with a DIFFERENT purpose than the still-active grant is rejected — failed-precondition", async () => {
  const organizationId = nextId("org");
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantCustomer(organizationId, uid);
  const requestKey = nextId("key");

  const first = await callCallable(
    GRANT_URL,
    validRequest({ organizationId, requestKey, purpose: "profileOnboarding" }),
    idToken,
  );
  assert.strictEqual(first.httpStatus, 200);

  const second = await callCallable(
    GRANT_URL,
    validRequest({ organizationId, requestKey }),
    idToken,
  );
  assert.strictEqual(second.httpStatus, 400);
  assert.strictEqual(second.body.error?.status, "FAILED_PRECONDITION");
});
