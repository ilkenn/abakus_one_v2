import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";

/**
 * Emulator-backed tests for `submitStockCount` + the `stockCountAdjustment`
 * `respondToApprovalRequest` integration — AP-5 Sprint 3. Mirrors this
 * codebase's established pattern (`assignReservationTable.test.ts` et al.):
 * raw HTTP against the callable wire protocol, staff identities minted via
 * anonymous sign-up + `setCustomUserClaims` + refresh-token.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SUBMIT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/submitStockCount`;
const RESPOND_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/respondToApprovalRequest`;

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

async function seedBranchStock(branchId: string, inventoryItemId: string, quantityOnHand: number) {
  await admin.firestore().collection("branchStock").doc(`${branchId}_${inventoryItemId}`).set({
    inventoryItemId,
    branchId,
    locationId: branchId,
    quantityOnHand,
    updatedAt: Timestamp.now(),
  });
}

test("submitStockCount: zero-discrepancy count auto-approves, no approval request, branchStock unchanged", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const itemId = nextId("item");
  await seedBranchStock(branchId, itemId, 100);

  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: [branchId] });
  const { body } = await callCallable(
    SUBMIT_URL,
    {
      organizationId: orgId,
      branchId,
      locationId: branchId,
      countedItems: [{ inventoryItemId: itemId, countedQuantitySmallestUnits: 100, unitCode: "g" }],
    },
    staffToken,
  );
  assert.strictEqual(body.result?.status, "approved", JSON.stringify(body));
  assert.strictEqual(body.result?.approvalRequestId, null);

  const stock = await admin.firestore().collection("branchStock").doc(`${branchId}_${itemId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 100);
});

test("submitStockCount: non-zero discrepancy stays submitted, creates a stockCountAdjustment approval request, never touches branchStock directly", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const itemId = nextId("item");
  await seedBranchStock(branchId, itemId, 100);

  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: [branchId] });
  const { body } = await callCallable(
    SUBMIT_URL,
    {
      organizationId: orgId,
      branchId,
      locationId: branchId,
      countedItems: [{ inventoryItemId: itemId, countedQuantitySmallestUnits: 85, unitCode: "g" }],
    },
    staffToken,
  );
  assert.strictEqual(body.result?.status, "submitted");
  assert.ok(body.result?.approvalRequestId, JSON.stringify(body));

  const stock = await admin.firestore().collection("branchStock").doc(`${branchId}_${itemId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 100); // untouched

  const countDoc = await admin.firestore().collection("stockCounts").doc(body.result!.countId as string).get();
  assert.strictEqual(countDoc.data()?.status, "submitted");
});

test("submitStockCount: staff without recordStockCount (courier role) is denied", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const itemId = nextId("item");
  const courierToken = await mintStaffIdToken(orgId, ["courier"], { [orgId]: [branchId] });

  const { body } = await callCallable(
    SUBMIT_URL,
    { organizationId: orgId, branchId, locationId: branchId, countedItems: [{ inventoryItemId: itemId, countedQuantitySmallestUnits: 1, unitCode: "g" }] },
    courierToken,
  );
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("stockCountAdjustment approval: manager-tier approving applies the correction, writes an inventoryAuditEntry, and marks the count completed", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const itemId = nextId("item");
  await seedBranchStock(branchId, itemId, 100);

  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: [branchId] });
  const managerToken = await mintStaffIdToken(orgId, ["manager"], { [orgId]: [branchId] });

  const submitted = await callCallable(
    SUBMIT_URL,
    { organizationId: orgId, branchId, locationId: branchId, countedItems: [{ inventoryItemId: itemId, countedQuantitySmallestUnits: 90, unitCode: "g" }] },
    staffToken,
  );
  const approvalRequestId = submitted.body.result!.approvalRequestId as string;

  const approved = await callCallable(RESPOND_URL, { requestId: approvalRequestId, decision: "approved" }, managerToken);
  assert.strictEqual(approved.body.result?.status, "approved", JSON.stringify(approved.body));

  const stock = await admin.firestore().collection("branchStock").doc(`${branchId}_${itemId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 90);

  const countDoc = await admin.firestore().collection("stockCounts").doc(submitted.body.result!.countId as string).get();
  assert.strictEqual(countDoc.data()?.status, "approved");

  const movements = await admin
    .firestore()
    .collection("stockMovements")
    .where("correlationId", "==", submitted.body.result!.countId)
    .where("type", "==", "countCorrection")
    .get();
  assert.strictEqual(movements.size, 1);
  assert.strictEqual(movements.docs[0].data().quantityDeltaSmallestUnits, -10);

  const auditEntries = await admin
    .firestore()
    .collection("inventoryAuditEntries")
    .where("targetEntityId", "==", submitted.body.result!.countId)
    .get();
  assert.strictEqual(auditEntries.size, 1);
  assert.strictEqual(auditEntries.docs[0].data().type, "stockCountApproved");
});

test("stockCountAdjustment approval: rejecting never touches branchStock, marks the count rejected", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const itemId = nextId("item");
  await seedBranchStock(branchId, itemId, 50);

  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: [branchId] });
  const managerToken = await mintStaffIdToken(orgId, ["manager"], { [orgId]: [branchId] });

  const submitted = await callCallable(
    SUBMIT_URL,
    { organizationId: orgId, branchId, locationId: branchId, countedItems: [{ inventoryItemId: itemId, countedQuantitySmallestUnits: 20, unitCode: "g" }] },
    staffToken,
  );
  const approvalRequestId = submitted.body.result!.approvalRequestId as string;

  const rejected = await callCallable(RESPOND_URL, { requestId: approvalRequestId, decision: "rejected" }, managerToken);
  assert.strictEqual(rejected.body.result?.status, "rejected");

  const stock = await admin.firestore().collection("branchStock").doc(`${branchId}_${itemId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 50); // untouched

  const countDoc = await admin.firestore().collection("stockCounts").doc(submitted.body.result!.countId as string).get();
  assert.strictEqual(countDoc.data()?.status, "rejected");
});

test("stockCountAdjustment approval: a wrong-branch manager is denied (branch-scoped response, mirrors the existing remoteApprovalMatrix pattern)", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const otherBranchId = nextId("branch");
  const itemId = nextId("item");
  await seedBranchStock(branchId, itemId, 40);

  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: [branchId] });
  const wrongBranchManagerToken = await mintStaffIdToken(orgId, ["manager"], { [orgId]: [otherBranchId] });

  const submitted = await callCallable(
    SUBMIT_URL,
    { organizationId: orgId, branchId, locationId: branchId, countedItems: [{ inventoryItemId: itemId, countedQuantitySmallestUnits: 45, unitCode: "g" }] },
    staffToken,
  );
  const approvalRequestId = submitted.body.result!.approvalRequestId as string;

  const { body } = await callCallable(RESPOND_URL, { requestId: approvalRequestId, decision: "approved" }, wrongBranchManagerToken);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");

  const stock = await admin.firestore().collection("branchStock").doc(`${branchId}_${itemId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 40); // untouched
});

test("stockCountAdjustment approval: the requester (staff who submitted) cannot approve their own count", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const itemId = nextId("item");
  await seedBranchStock(branchId, itemId, 30);

  // A manager both submits AND tries to approve their own submission.
  const managerToken = await mintStaffIdToken(orgId, ["manager"], { [orgId]: [branchId] });

  const submitted = await callCallable(
    SUBMIT_URL,
    { organizationId: orgId, branchId, locationId: branchId, countedItems: [{ inventoryItemId: itemId, countedQuantitySmallestUnits: 33, unitCode: "g" }] },
    managerToken,
  );
  const approvalRequestId = submitted.body.result!.approvalRequestId as string;

  const { body } = await callCallable(RESPOND_URL, { requestId: approvalRequestId, decision: "approved" }, managerToken);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});
