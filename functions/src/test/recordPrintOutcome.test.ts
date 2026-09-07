import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for the `recordPrintOutcome` callable — AP-5
 * Sprint 4. Same raw-HTTP-against-the-callable-wire-protocol pattern as
 * `requestPrintJob.test.ts`/`stockCountReconciliation.test.ts`.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const REQUEST_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/requestPrintJob`;
const RECORD_OUTCOME_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/recordPrintOutcome`;

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

async function signUpAnonymously(): Promise<{ idToken: string; refreshToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken: string; refreshToken: string; localId: string };
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}

async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  const body = (await response.json()) as { id_token: string };
  return body.id_token;
}

async function mintStaffIdToken(
  organizationId: string,
  roles: string[],
  branchAccess: Record<string, string[]>,
): Promise<string> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, {
    organizationAccess: [organizationId],
    roles: { [organizationId]: roles },
    branchAccess,
  });
  return refreshIdToken(refreshToken);
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

test("recordPrintOutcome: manually flips a failed job to success (staff confirms it printed by other means)", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: [branchId] });

  // No printerConfigs seeded -> the mock transport resolves this to failed.
  const requested = await callCallable(
    REQUEST_URL,
    { organizationId: orgId, branchId, orderId, stationId: "shared" },
    staffToken,
  );
  assert.strictEqual(requested.body.result?.status, "failed", JSON.stringify(requested.body));
  const printJobId = requested.body.result!.printJobId as string;

  const { body } = await callCallable(
    RECORD_OUTCOME_URL,
    { printJobId, outcome: "success" },
    staffToken,
  );
  assert.strictEqual(body.result?.status, "success", JSON.stringify(body));

  const jobDoc = await admin.firestore().collection("printJobs").doc(printJobId).get();
  assert.strictEqual(jobDoc.data()?.status, "success");
});

async function seedPrinterConfig(branchId: string, stationId: string) {
  await admin.firestore().collection("printerConfigs").doc(nextId("printer")).set({
    organizationId: "org-1",
    branchId,
    stationId,
    transport: "network",
    isBackup: false,
  });
}

test("recordPrintOutcome: a job that already succeeded is genuinely terminal — a later call can never demote it back to failed", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const orderId = nextId("order");
  await seedPrinterConfig(branchId, "shared");
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: [branchId] });

  const requested = await callCallable(
    REQUEST_URL,
    { organizationId: orgId, branchId, orderId, stationId: "shared" },
    staffToken,
  );
  const printJobId = requested.body.result!.printJobId as string;
  assert.strictEqual(requested.body.result?.status, "success");

  const attemptedDemoteToFailed = await callCallable(
    RECORD_OUTCOME_URL,
    { printJobId, outcome: "failed" },
    staffToken,
  );
  // Already terminal `success` — the outcome is NOT overwritten.
  assert.strictEqual(attemptedDemoteToFailed.body.result?.status, "success");

  const jobDoc = await admin.firestore().collection("printJobs").doc(printJobId).get();
  assert.strictEqual(jobDoc.data()?.status, "success");
});

test("recordPrintOutcome: an unknown printJobId is rejected as not-found", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: [branchId] });

  const { body } = await callCallable(
    RECORD_OUTCOME_URL,
    { printJobId: nextId("nonexistent-print-job"), outcome: "success" },
    staffToken,
  );
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});

test("recordPrintOutcome: staff without manageKitchenOperations (courier role) is denied", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: [branchId] });
  const courierToken = await mintStaffIdToken(orgId, ["courier"], { [orgId]: [branchId] });

  const requested = await callCallable(
    REQUEST_URL,
    { organizationId: orgId, branchId, orderId, stationId: "shared" },
    staffToken,
  );
  const printJobId = requested.body.result!.printJobId as string;

  const { body } = await callCallable(
    RECORD_OUTCOME_URL,
    { printJobId, outcome: "success" },
    courierToken,
  );
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});
