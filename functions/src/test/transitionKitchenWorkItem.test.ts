import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `transitionKitchenWorkItem` — AP-5 Sprint 1.
 * Mirrors this codebase's established pattern (`assignReservationTable
 * .test.ts` et al.): raw HTTP against the callable wire protocol, staff
 * identities minted via anonymous sign-up + `setCustomUserClaims` +
 * refresh-token, Firestore fixtures seeded directly via the Admin SDK
 * (bypassing rules — this suite tests the callable, not `firestore.rules`;
 * that is `firestore-tests/rules.test.js`'s job).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const TRANSITION_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/transitionKitchenWorkItem`;

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
  assert.strictEqual(response.status, 200, "Auth emulator sign-up must succeed");
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
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

async function seedWorkItem(fields: {
  organizationId: string;
  branchId: string;
  orderId: string;
  status: string;
  revision: number;
}): Promise<string> {
  const id = nextId("work-item");
  await admin.firestore().collection("kitchenWorkItems").doc(id).set({
    organizationId: fields.organizationId,
    branchId: fields.branchId,
    orderId: fields.orderId,
    kitchenTicketId: nextId("ticket"),
    kitchenTicketLineId: nextId("line"),
    status: fields.status,
    revision: fields.revision,
  });
  return id;
}

test("transitionKitchenWorkItem: unauthenticated is denied", async () => {
  const orgId = nextId("org");
  const workItemId = await seedWorkItem({
    organizationId: orgId, branchId: "branch-1", orderId: nextId("order"), status: "queued", revision: 1,
  });
  const { body } = await callCallable(TRANSITION_URL, {
    workItemId, to: "acknowledged", expectedRevision: 1,
  });
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("transitionKitchenWorkItem: a different branch's staff is denied", async () => {
  const orgId = nextId("org");
  const workItemId = await seedWorkItem({
    organizationId: orgId, branchId: "branch-1", orderId: nextId("order"), status: "queued", revision: 1,
  });
  const wrongBranchToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: ["branch-2"] });
  const { body } = await callCallable(
    TRANSITION_URL,
    { workItemId, to: "acknowledged", expectedRevision: 1 },
    wrongBranchToken,
  );
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("transitionKitchenWorkItem: an org member without the kitchen permission (courier role) is denied", async () => {
  const orgId = nextId("org");
  const workItemId = await seedWorkItem({
    organizationId: orgId, branchId: "branch-1", orderId: nextId("order"), status: "queued", revision: 1,
  });
  const courierToken = await mintStaffIdToken(orgId, ["courier"], { [orgId]: ["branch-1"] });
  const { body } = await callCallable(
    TRANSITION_URL,
    { workItemId, to: "acknowledged", expectedRevision: 1 },
    courierToken,
  );
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("transitionKitchenWorkItem: a valid staff performs queued -> acknowledged -> preparing -> ready", async () => {
  const orgId = nextId("org");
  const orderId = nextId("order");
  const workItemId = await seedWorkItem({
    organizationId: orgId, branchId: "branch-1", orderId, status: "queued", revision: 1,
  });
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: ["branch-1"] });

  const step1 = await callCallable(TRANSITION_URL, { workItemId, to: "acknowledged", expectedRevision: 1 }, staffToken);
  assert.strictEqual(step1.httpStatus, 200, JSON.stringify(step1.body));
  assert.strictEqual(step1.body.result?.status, "acknowledged");
  assert.strictEqual(step1.body.result?.revision, 2);

  const step2 = await callCallable(TRANSITION_URL, { workItemId, to: "preparing", expectedRevision: 2 }, staffToken);
  assert.strictEqual(step2.body.result?.status, "preparing");
  assert.strictEqual(step2.body.result?.revision, 3);

  const step3 = await callCallable(TRANSITION_URL, { workItemId, to: "ready", expectedRevision: 3 }, staffToken);
  assert.strictEqual(step3.body.result?.status, "ready");
  assert.strictEqual(step3.body.result?.revision, 4);
  // Only sibling for this order -> all siblings ready.
  assert.strictEqual(step3.body.result?.allSiblingsReady, true);
  assert.strictEqual(step3.body.result?.orderId, orderId);

  const snap = await admin.firestore().collection("kitchenWorkItems").doc(workItemId).get();
  assert.strictEqual(snap.data()?.status, "ready");
  assert.strictEqual(snap.data()?.revision, 4);
  assert.ok(snap.data()?.readyAt);
});

test("transitionKitchenWorkItem: a stale expectedRevision is rejected (optimistic concurrency)", async () => {
  const orgId = nextId("org");
  const workItemId = await seedWorkItem({
    organizationId: orgId, branchId: "branch-1", orderId: nextId("order"), status: "queued", revision: 1,
  });
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: ["branch-1"] });

  const { body } = await callCallable(
    TRANSITION_URL,
    { workItemId, to: "acknowledged", expectedRevision: 99 },
    staffToken,
  );
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("transitionKitchenWorkItem: an invalid transition (queued -> ready, skipping steps) is rejected", async () => {
  const orgId = nextId("org");
  const workItemId = await seedWorkItem({
    organizationId: orgId, branchId: "branch-1", orderId: nextId("order"), status: "queued", revision: 1,
  });
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: ["branch-1"] });

  const { body } = await callCallable(
    TRANSITION_URL,
    { workItemId, to: "ready", expectedRevision: 1 },
    staffToken,
  );
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("transitionKitchenWorkItem: a ready-completed line never silently returns to preparing — only recalled is a valid next step", async () => {
  const orgId = nextId("org");
  const workItemId = await seedWorkItem({
    organizationId: orgId, branchId: "branch-1", orderId: nextId("order"), status: "ready", revision: 4,
  });
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: ["branch-1"] });

  const invalid = await callCallable(
    TRANSITION_URL,
    { workItemId, to: "preparing", expectedRevision: 4 },
    staffToken,
  );
  assert.strictEqual(invalid.body.error?.status, "FAILED_PRECONDITION");

  const valid = await callCallable(
    TRANSITION_URL,
    { workItemId, to: "recalled", expectedRevision: 4 },
    staffToken,
  );
  assert.strictEqual(valid.body.result?.status, "recalled");
});

test("transitionKitchenWorkItem: allSiblingsReady is false until every work item for the order is ready or cancelled", async () => {
  const orgId = nextId("org");
  const orderId = nextId("order");
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: ["branch-1"] });

  const itemA = await seedWorkItem({ organizationId: orgId, branchId: "branch-1", orderId, status: "preparing", revision: 3 });
  const itemB = await seedWorkItem({ organizationId: orgId, branchId: "branch-1", orderId, status: "preparing", revision: 3 });

  const firstReady = await callCallable(TRANSITION_URL, { workItemId: itemA, to: "ready", expectedRevision: 3 }, staffToken);
  assert.strictEqual(firstReady.body.result?.allSiblingsReady, false);

  const secondReady = await callCallable(TRANSITION_URL, { workItemId: itemB, to: "ready", expectedRevision: 3 }, staffToken);
  assert.strictEqual(secondReady.body.result?.allSiblingsReady, true);
});

test("transitionKitchenWorkItem: a ready transition returns the order's channel so the client can pick the right advance*OrderStatus callable", async () => {
  const orgId = nextId("org");
  const orderId = nextId("order");
  await admin.firestore().collection("orders").doc(orderId).set({
    organizationId: orgId, branchId: "branch-1", channel: "takeaway", status: "preparing",
  });
  const workItemId = await seedWorkItem({
    organizationId: orgId, branchId: "branch-1", orderId, status: "preparing", revision: 3,
  });
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: ["branch-1"] });

  const { body } = await callCallable(TRANSITION_URL, { workItemId, to: "ready", expectedRevision: 3 }, staffToken);
  assert.strictEqual(body.result?.orderChannel, "takeaway");
});

test("transitionKitchenWorkItem: allSiblingsReady treats a cancelled sibling as satisfied, not blocking", async () => {
  const orgId = nextId("org");
  const orderId = nextId("order");
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: ["branch-1"] });

  const itemA = await seedWorkItem({ organizationId: orgId, branchId: "branch-1", orderId, status: "preparing", revision: 3 });
  const itemB = await seedWorkItem({ organizationId: orgId, branchId: "branch-1", orderId, status: "queued", revision: 1 });

  await callCallable(TRANSITION_URL, { workItemId: itemB, to: "cancelled", expectedRevision: 1 }, staffToken);
  const readyResult = await callCallable(TRANSITION_URL, { workItemId: itemA, to: "ready", expectedRevision: 3 }, staffToken);
  assert.strictEqual(readyResult.body.result?.allSiblingsReady, true);
});

test("transitionKitchenWorkItem: AP-5 Sprint 3 — ready -> wasted is now a valid transition, and wasted is itself terminal (no further transition succeeds)", async () => {
  const orgId = nextId("org");
  const workItemId = await seedWorkItem({
    organizationId: orgId, branchId: "branch-1", orderId: nextId("order"), status: "ready", revision: 4,
  });
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: ["branch-1"] });

  const wasted = await callCallable(TRANSITION_URL, { workItemId, to: "wasted", expectedRevision: 4 }, staffToken);
  assert.strictEqual(wasted.body.result?.status, "wasted", JSON.stringify(wasted.body));

  const noFurtherTransition = await callCallable(
    TRANSITION_URL,
    { workItemId, to: "recalled", expectedRevision: 5 },
    staffToken,
  );
  assert.strictEqual(noFurtherTransition.body.error?.status, "FAILED_PRECONDITION");
});

test("transitionKitchenWorkItem: AP-5 Sprint 3 — preparing -> wasted is also valid (not just ready)", async () => {
  const orgId = nextId("org");
  const workItemId = await seedWorkItem({
    organizationId: orgId, branchId: "branch-1", orderId: nextId("order"), status: "preparing", revision: 3,
  });
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: ["branch-1"] });

  const wasted = await callCallable(TRANSITION_URL, { workItemId, to: "wasted", expectedRevision: 3 }, staffToken);
  assert.strictEqual(wasted.body.result?.status, "wasted");
});

test("transitionKitchenWorkItem: AP-5 Sprint 3 — queued/acknowledged cannot go directly to wasted (only cancelled) — nothing was consumed yet to waste", async () => {
  const orgId = nextId("org");
  const workItemId = await seedWorkItem({
    organizationId: orgId, branchId: "branch-1", orderId: nextId("order"), status: "queued", revision: 1,
  });
  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: ["branch-1"] });

  const { body } = await callCallable(TRANSITION_URL, { workItemId, to: "wasted", expectedRevision: 1 }, staffToken);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});
