import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for the `processAccountDeletion` HTTPS callable
 * function — Sprint 9G (docs/decisions.md ADR-026). Run via
 * `npm run test:emulator`. Calls the callable function directly over
 * HTTP using the documented callable-functions wire protocol
 * (`{"data": ...}` request body, `{"result": ...}`/`{"error": ...}`
 * response) rather than adding the `firebase` client SDK as a new
 * dependency just for this test file.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const FUNCTION_URL =
  `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/processAccountDeletion`;

let app: admin.app.App;

before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});

after(async () => {
  await app.delete();
});

async function callProcessAccountDeletion(requestId: string) {
  const response = await fetch(FUNCTION_URL, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ data: { requestId } }),
  });
  const body = (await response.json()) as {
    result?: unknown;
    error?: { status?: string; message?: string };
  };
  return { httpStatus: response.status, body };
}

test("processAccountDeletion anonymizes the linked customer and marks the request completed", async () => {
  const db = admin.firestore();
  const requestId = "test-deletion-1";
  const uid = "uid-deletion-1";
  const pastDue = new Date(Date.now() - 60_000).toISOString();

  await db.collection("customers").doc(uid).set({
    displayName: "Ahmet Yılmaz",
    phoneNumber: "+905551234567",
    accountStatus: "active",
  });
  await db.collection("deletionRequests").doc(requestId).set({
    uid,
    status: "coolingOff",
    requestedAt: pastDue,
    coolingOffEndsAt: pastDue,
  });

  const { httpStatus, body } = await callProcessAccountDeletion(requestId);

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
  const requestId = "test-deletion-2";
  const uid = "uid-deletion-2";
  const pastDue = new Date(Date.now() - 60_000).toISOString();

  await db.collection("customers").doc(uid).set({
    displayName: "Original Name",
    phoneNumber: "+905550000000",
    accountStatus: "active",
  });
  await db.collection("deletionRequests").doc(requestId).set({
    uid,
    status: "coolingOff",
    requestedAt: pastDue,
    coolingOffEndsAt: pastDue,
  });

  const first = await callProcessAccountDeletion(requestId);
  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(
    (first.body.result as { alreadyProcessed: boolean }).alreadyProcessed,
    false,
  );

  const second = await callProcessAccountDeletion(requestId);
  assert.strictEqual(second.httpStatus, 200);
  assert.deepStrictEqual(second.body.result, {
    status: "completed",
    alreadyProcessed: true,
  });
});

test("processAccountDeletion fails closed - refuses a request whose cooling-off window has not elapsed", async () => {
  const db = admin.firestore();
  const requestId = "test-deletion-3";
  const uid = "uid-deletion-3";
  const future = new Date(Date.now() + 60 * 60 * 1000).toISOString();

  await db.collection("customers").doc(uid).set({
    displayName: "Still Active",
    phoneNumber: "+905559999999",
    accountStatus: "active",
  });
  await db.collection("deletionRequests").doc(requestId).set({
    uid,
    status: "coolingOff",
    requestedAt: new Date().toISOString(),
    coolingOffEndsAt: future,
  });

  const { httpStatus, body } = await callProcessAccountDeletion(requestId);

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");

  const customer = (await db.collection("customers").doc(uid).get()).data();
  assert.strictEqual(customer?.displayName, "Still Active");
});

test("processAccountDeletion fails closed - refuses an unknown requestId", async () => {
  const { httpStatus, body } = await callProcessAccountDeletion(
    "does-not-exist",
  );

  assert.strictEqual(httpStatus, 404);
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});
