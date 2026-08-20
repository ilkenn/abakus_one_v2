import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for the `processAccountDeletion` HTTPS callable
 * function — Sprint 9G (docs/decisions.md ADR-026), authorization hardened
 * Faz D.3.2.1 (Account Deletion Authorization + App Check Fail-Safe
 * Audit). Run via `npm run test:emulator`. Calls the callable function
 * directly over HTTP using the documented callable-functions wire
 * protocol (`{"data": ...}` request body, `{"result": ...}`/
 * `{"error": ...}` response, `Authorization: Bearer <idToken>` for an
 * authenticated call) — same pattern as `submitTakeawayOrder.test.ts`.
 *
 * **Every test in this file now authenticates as a real phone-verified
 * customer whose own uid matches the seeded `deletionRequests` document
 * — this is the correct, secure shape of a call to this endpoint.** Prior
 * to Faz D.3.2.1, this function had no `request.auth` check at all, and
 * every test here called it completely unauthenticated; those 4 original
 * tests are preserved (still proving idempotency, the not-yet-due
 * precondition, and the unknown-id case) but now exercise the real,
 * secure caller shape rather than the vulnerability itself.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const FUNCTION_URL =
  `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/processAccountDeletion`;

let app: admin.app.App;

before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});

after(async () => {
  await app.delete();
});

async function callProcessAccountDeletion(
  data: Record<string, unknown>,
  idToken?: string,
) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers,
    body: JSON.stringify({ data }),
  });
  const body = (await response.json()) as {
    result?: unknown;
    error?: { status?: string; message?: string };
  };
  return { httpStatus: response.status, body };
}

async function createAnonymousUser(): Promise<{ idToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const body = (await response.json()) as { idToken: string; localId: string };
  return { idToken: body.idToken, uid: body.localId };
}

// Faz R.1C.1.1 — a per-file random namespace so phone numbers can never
// collide with another test file's, closing the same class of shared-
// emulator-state leakage root-caused in `respondToReservation.test.ts`
// (see that file's own comment for the full story).
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
  const codesRes = await fetch(
    `${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`,
  );
  const codesBody = (await codesRes.json()) as {
    verificationCodes: { sessionInfo: string; code: string }[];
  };
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

async function seedDeletionRequest(
  requestId: string,
  uid: string,
  overrides: Record<string, unknown> = {},
) {
  const db = admin.firestore();
  const pastDue = new Date(Date.now() - 60_000).toISOString();
  await db.collection("deletionRequests").doc(requestId).set({
    uid,
    status: "coolingOff",
    requestedAt: pastDue,
    coolingOffEndsAt: pastDue,
    ...overrides,
  });
}

test("processAccountDeletion anonymizes the linked customer and marks the request completed — real phone customer processing their own request", async () => {
  const db = admin.firestore();
  const { idToken, uid } = await createRealPhoneUser();
  const requestId = "test-deletion-1";

  await db.collection("customers").doc(uid).set({
    displayName: "Ahmet Yılmaz",
    phoneNumber: "+905551234567",
    accountStatus: "active",
  });
  await seedDeletionRequest(requestId, uid);

  const { httpStatus, body } = await callProcessAccountDeletion({ requestId }, idToken);

  assert.strictEqual(httpStatus, 200);
  assert.deepStrictEqual(body.result, {
    status: "completed",
    alreadyProcessed: false,
  });

  const customer = (await db.collection("customers").doc(uid).get()).data();
  assert.strictEqual(customer?.displayName, "Silinmiş Kullanıcı");
  assert.strictEqual(customer?.phoneNumber, "");
  assert.strictEqual(customer?.accountStatus, "restricted");

  const request = (
    await db.collection("deletionRequests").doc(requestId).get()
  ).data();
  assert.strictEqual(request?.status, "completed");
  assert.ok(request?.completedAt);

  const audit = await db
    .collection("accountDeletionAuditEvents")
    .doc(`${requestId}-completed`)
    .get();
  assert.ok(audit.exists);
  const auditData = audit.data()!;
  assert.strictEqual(Object.keys(auditData).sort().join(","), [
    "recordedAt",
    "requestId",
    "type",
  ].sort().join(","));
});

test("processAccountDeletion is idempotent - calling it twice does not re-anonymize or error", async () => {
  const db = admin.firestore();
  const { idToken, uid } = await createRealPhoneUser();
  const requestId = "test-deletion-2";

  await db.collection("customers").doc(uid).set({
    displayName: "Original Name",
    phoneNumber: "+905550000000",
    accountStatus: "active",
  });
  await seedDeletionRequest(requestId, uid);

  const first = await callProcessAccountDeletion({ requestId }, idToken);
  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(
    (first.body.result as { alreadyProcessed: boolean }).alreadyProcessed,
    false,
  );

  const second = await callProcessAccountDeletion({ requestId }, idToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.deepStrictEqual(second.body.result, {
    status: "completed",
    alreadyProcessed: true,
  });
});

test("processAccountDeletion fails closed - refuses a request whose cooling-off window has not elapsed", async () => {
  const db = admin.firestore();
  const { idToken, uid } = await createRealPhoneUser();
  const requestId = "test-deletion-3";
  const future = new Date(Date.now() + 60 * 60 * 1000).toISOString();

  await db.collection("customers").doc(uid).set({
    displayName: "Still Active",
    phoneNumber: "+905559999999",
    accountStatus: "active",
  });
  await seedDeletionRequest(requestId, uid, {
    requestedAt: new Date().toISOString(),
    coolingOffEndsAt: future,
  });

  const { httpStatus, body } = await callProcessAccountDeletion({ requestId }, idToken);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");

  const customer = (await db.collection("customers").doc(uid).get()).data();
  assert.strictEqual(customer?.displayName, "Still Active");
});

test("processAccountDeletion fails closed - refuses an unknown requestId (authenticated caller, id simply does not exist)", async () => {
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callProcessAccountDeletion(
    { requestId: "does-not-exist" },
    idToken,
  );

  assert.strictEqual(httpStatus, 404);
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});

// =====================================================================
// Faz D.3.2.1 — authorization hardening. Prior to this phase, none of
// these were checked: requestId is sequential/guessable
// (`SequentialAccountDeletionRequestIdGenerator`), and this function had
// no `request.auth` check of any kind — any caller, unauthenticated or
// anonymous, could complete another customer's already-due deletion by
// guessing its id.
// =====================================================================

test("Faz D.3.2.1: an unauthenticated caller is denied outright — no request.auth at all", async () => {
  const db = admin.firestore();
  const requestId = "test-deletion-unauth";
  await db.collection("customers").doc("uid-unauth-target").set({
    displayName: "Target",
    phoneNumber: "+905550000001",
    accountStatus: "active",
  });
  await seedDeletionRequest(requestId, "uid-unauth-target");

  const { httpStatus, body } = await callProcessAccountDeletion({ requestId });

  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");

  const customer = (await db.collection("customers").doc("uid-unauth-target").get()).data();
  assert.strictEqual(customer?.displayName, "Target", "no anonymization must occur");
});

test("Faz D.3.2.1: an anonymous technical identity is denied — real customer account deletion never accepts a non-phone-verified caller", async () => {
  const db = admin.firestore();
  const { idToken } = await createAnonymousUser();
  const requestId = "test-deletion-anon";
  await db.collection("customers").doc("uid-anon-target").set({
    displayName: "Target",
    phoneNumber: "+905550000002",
    accountStatus: "active",
  });
  await seedDeletionRequest(requestId, "uid-anon-target");

  const { httpStatus, body } = await callProcessAccountDeletion({ requestId }, idToken);

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");

  const customer = (await db.collection("customers").doc("uid-anon-target").get()).data();
  assert.strictEqual(customer?.displayName, "Target", "no anonymization must occur");
});

test("Faz D.3.2.1: a real phone customer cannot process another customer's deletion request by supplying its (guessable, sequential) requestId — resolves not-found, identical to a genuinely unknown id, never confirming the request exists", async () => {
  const db = admin.firestore();
  const owner = await createRealPhoneUser();
  const attacker = await createRealPhoneUser();
  const requestId = "test-deletion-cross-account";

  await db.collection("customers").doc(owner.uid).set({
    displayName: "Real Owner",
    phoneNumber: "+905550000003",
    accountStatus: "active",
  });
  await seedDeletionRequest(requestId, owner.uid);

  const { httpStatus, body } = await callProcessAccountDeletion(
    { requestId },
    attacker.idToken,
  );

  assert.strictEqual(httpStatus, 404);
  assert.strictEqual(
    body.error?.status,
    "NOT_FOUND",
    "must be indistinguishable from a genuinely unknown requestId — never an oracle for another account's request",
  );

  const customer = (await db.collection("customers").doc(owner.uid).get()).data();
  assert.strictEqual(customer?.displayName, "Real Owner", "the real owner's account must be untouched");
  const request = (await db.collection("deletionRequests").doc(requestId).get()).data();
  assert.strictEqual(request?.status, "coolingOff", "the real owner's request must remain unprocessed");
});

// =====================================================================
// Customer Registration CR.1 (2026-08-19) — deleted accounts must not
// retain the new registration-form PII fields either. `tenantCustomers`
// is deliberately left alone (see processAccountDeletion.ts's own
// updated doc comment) — it carries no PII to redact.
// =====================================================================

test("CR.1/CR.1.1: account deletion redacts firstName/lastName/email/workplaceName/educationalInstitutionName/gender/occupationStatus/birthDate, and leaves tenantCustomers untouched", async () => {
  const db = admin.firestore();
  const { idToken, uid } = await createRealPhoneUser();
  const requestId = "test-deletion-cr1-pii";

  const membershipRef = db.collection("tenantCustomers").doc(`org-1_${uid}`);
  await db.collection("customers").doc(uid).set({
    uid,
    firstName: "Ayşe",
    lastName: "Yılmaz",
    displayName: "Ayşe Yılmaz",
    email: "ayse@example.com",
    phoneNumber: "+905551110000",
    accountStatus: "active",
    occupationStatus: "working",
    workplaceName: "Abaküs Kahve",
    educationalInstitutionName: null,
    gender: "female",
    birthDate: "1990-08-20",
    profileCompletedAt: admin.firestore.Timestamp.now(),
    createdAt: admin.firestore.Timestamp.now(),
    updatedAt: admin.firestore.Timestamp.now(),
  });
  await membershipRef.set({
    organizationId: "org-1",
    uid,
    createdAt: admin.firestore.Timestamp.now(),
  });
  await seedDeletionRequest(requestId, uid);

  const { httpStatus } = await callProcessAccountDeletion({ requestId }, idToken);
  assert.strictEqual(httpStatus, 200);

  const customer = (await db.collection("customers").doc(uid).get()).data();
  assert.strictEqual(customer?.displayName, "Silinmiş Kullanıcı");
  assert.strictEqual(customer?.phoneNumber, "");
  assert.strictEqual(customer?.accountStatus, "restricted");
  assert.strictEqual(customer?.firstName, "");
  assert.strictEqual(customer?.lastName, "");
  assert.strictEqual(customer?.email, "");
  assert.strictEqual(customer?.workplaceName, null);
  assert.strictEqual(customer?.educationalInstitutionName, null);
  assert.strictEqual(customer?.gender, null);
  assert.strictEqual(customer?.occupationStatus, null);
  assert.strictEqual(customer?.birthDate, null, "CR.1.1: birthDate is PII and must be redacted on deletion");

  // tenantCustomers carries no PII — deliberately untouched, not
  // deleted, not anonymized (see the audit reasoning above).
  const membership = (await membershipRef.get()).data();
  assert.strictEqual(membership?.organizationId, "org-1");
  assert.strictEqual(membership?.uid, uid);
});

test("Faz D.3.2.1: a client-supplied uid field on the payload is never read — the affected account always comes from the deletionRequests document's own server-written uid, never from the request body", async () => {
  const db = admin.firestore();
  const { idToken, uid } = await createRealPhoneUser();
  const otherUid = "uid-payload-spoof-target";
  const requestId = "test-deletion-payload-uid-ignored";

  await db.collection("customers").doc(uid).set({
    displayName: "Real Caller",
    phoneNumber: "+905550000004",
    accountStatus: "active",
  });
  await db.collection("customers").doc(otherUid).set({
    displayName: "Should Not Be Touched",
    phoneNumber: "+905550000005",
    accountStatus: "active",
  });
  await seedDeletionRequest(requestId, uid);

  // Caller owns this requestId, but also (irrelevantly) claims a
  // different uid in the payload — must have zero effect either way.
  const { httpStatus } = await callProcessAccountDeletion(
    { requestId, uid: otherUid },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const caller = (await db.collection("customers").doc(uid).get()).data();
  assert.strictEqual(caller?.displayName, "Silinmiş Kullanıcı", "the real caller's own account is the one processed");
  const other = (await db.collection("customers").doc(otherUid).get()).data();
  assert.strictEqual(other?.displayName, "Should Not Be Touched", "the payload-supplied uid must never be used");
});
