import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for the `requestPrintJob` callable — AP-5
 * Sprint 4. Mirrors `stockCountReconciliation.test.ts`'s established
 * pattern exactly: raw HTTP against the callable wire protocol, staff
 * identities minted via anonymous sign-up + `setCustomUserClaims` +
 * refresh-token.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const REQUEST_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/requestPrintJob`;

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

async function seedPrinterConfig(branchId: string, stationId: string) {
  await admin.firestore().collection("printerConfigs").doc(nextId("printer")).set({
    organizationId: "org-1",
    branchId,
    stationId,
    transport: "network",
    isBackup: false,
  });
}

test("requestPrintJob: a registered printer resolves the job to success", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const orderId = nextId("order");
  await seedPrinterConfig(branchId, "shared");
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: [branchId] });

  const { body } = await callCallable(
    REQUEST_URL,
    { organizationId: orgId, branchId, orderId, stationId: "shared" },
    staffToken,
  );
  assert.strictEqual(body.result?.status, "success", JSON.stringify(body));

  const jobId = body.result!.printJobId as string;
  const jobDoc = await admin.firestore().collection("printJobs").doc(jobId).get();
  assert.strictEqual(jobDoc.data()?.status, "success");
});

test("requestPrintJob: no registered printer resolves the job to failed", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: [branchId] });

  const { body } = await callCallable(
    REQUEST_URL,
    { organizationId: orgId, branchId, orderId, stationId: "shared" },
    staffToken,
  );
  assert.strictEqual(body.result?.status, "failed", JSON.stringify(body));
});

test("requestPrintJob: a duplicate non-copy call for the same order/station returns the same job, never a second document", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const orderId = nextId("order");
  await seedPrinterConfig(branchId, "shared");
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: [branchId] });

  const first = await callCallable(
    REQUEST_URL,
    { organizationId: orgId, branchId, orderId, stationId: "shared" },
    staffToken,
  );
  const second = await callCallable(
    REQUEST_URL,
    { organizationId: orgId, branchId, orderId, stationId: "shared" },
    staffToken,
  );
  assert.strictEqual(first.body.result?.printJobId, second.body.result?.printJobId);

  const snap = await admin
    .firestore()
    .collection("printJobs")
    .where("orderId", "==", orderId)
    .get();
  assert.strictEqual(snap.size, 1);
});

test("requestPrintJob: isCopy always opens a brand-new job at the next generation, never mutating the original", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const orderId = nextId("order");
  await seedPrinterConfig(branchId, "shared");
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: [branchId] });

  const original = await callCallable(
    REQUEST_URL,
    { organizationId: orgId, branchId, orderId, stationId: "shared" },
    staffToken,
  );
  const reprint = await callCallable(
    REQUEST_URL,
    { organizationId: orgId, branchId, orderId, stationId: "shared", isCopy: true },
    staffToken,
  );

  assert.notStrictEqual(original.body.result?.printJobId, reprint.body.result?.printJobId);
  assert.strictEqual(reprint.body.result?.printJobId, `print-${orderId}-shared-gen1`);

  const snap = await admin
    .firestore()
    .collection("printJobs")
    .where("orderId", "==", orderId)
    .get();
  assert.strictEqual(snap.size, 2);

  const originalDoc = snap.docs.find((d) => d.id === original.body.result?.printJobId)!;
  assert.strictEqual(originalDoc.data().isCopy, false);
  const reprintDoc = snap.docs.find((d) => d.id === reprint.body.result?.printJobId)!;
  assert.strictEqual(reprintDoc.data().isCopy, true);
});

test("requestPrintJob: staff without manageKitchenOperations (courier role) is denied", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const courierToken = await mintStaffIdToken(orgId, ["courier"], { [orgId]: [branchId] });

  const { body } = await callCallable(
    REQUEST_URL,
    { organizationId: orgId, branchId, orderId, stationId: "shared" },
    courierToken,
  );
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});
