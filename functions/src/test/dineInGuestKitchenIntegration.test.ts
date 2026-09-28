import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Closes a real coverage gap found auditing the QR table-guest ordering
 * flow end to end: `dineInCanonicalLifecycle.test.ts` exercises the real
 * guest-auth -> real staff-permission-flow accept chain but never asserts a
 * `kitchenWorkItems` doc actually gets created; `orderAcceptanceStockIntegration
 * .test.ts` asserts the `kitchenWorkItems` doc but seeds the order directly
 * via the Admin SDK and mints the staff token via `setCustomUserClaims`
 * directly, bypassing `submitDineInOrder`'s guest-ownership check and the
 * real membership/role-grant pipeline entirely. Neither test proves the
 * whole real chain — real anonymous guest auth, through the real ownership/
 * table-session checks in `submitDineInOrder`, through the real staff
 * permission/branch-access checks in `respondToDineInOrderLines`, all the
 * way to a `kitchenWorkItems` doc carrying the right station — in one place.
 * This test does. Helper shapes mirror `dineInCanonicalLifecycle.test.ts`'s
 * own (that file's own header notes it mirrors `ap3E2E.test.ts`'s
 * `seedGuestAtTable` too) — no shared test-support module exists for this
 * suite, so every file keeps its own copy, matching established convention.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_DINE_IN_URL = fn("submitDineInOrder");
const RESPOND_LINES_URL = fn("respondToDineInOrderLines");
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const ASSIGN_ROLE_URL = fn("assignStaffRole");
const GRANT_BRANCH_URL = fn("grantStaffBranchAccess");

let app: admin.app.App;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID }); });
after(async () => { await app.delete(); });
const db = () => admin.firestore();

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as { result?: Record<string, unknown>; error?: { status?: string; message?: string } };
  return { httpStatus: response.status, body };
}

async function signUpAnonymously(): Promise<{ idToken: string; refreshToken: string; uid: string }> {
  const response = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }),
  });
  const body = (await response.json()) as { idToken: string; refreshToken: string; localId: string };
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}
async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  const body = (await response.json()) as { id_token: string };
  return body.id_token;
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function seedTenant() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  await db().collection("branches").doc(branchId).set({ restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false });
  await db().collection("entitlements").doc(`${organizationId}_organization_${organizationId}_pos`).set({
    organizationId, scopeType: "organization", scopeId: organizationId, module: "pos", status: "active", version: 1,
  });
  return { organizationId, restaurantId, branchId };
}

/** A real category->station default (`catalogMigration.ts`'s own migrated
 * shape) plus a product routed through it — so a guest-submitted line's
 * `kitchenWorkItems.station` proves real routing, not just the `"shared"`
 * fallback every other integration test happens to exercise by omission. */
async function seedMenuProductWithStation(
  id: string, restaurantId: string, organizationId: string, categoryId: string, defaultStation: string,
) {
  await db().collection("menuCategories").doc(categoryId).set({
    organizationId, name: "Test Category", sortOrder: 0, isActive: true, defaultStation,
  });
  await db().collection("menuProducts").doc(id).set({
    organizationId, restaurantId, categoryId, name: "Test Product",
    basePriceMinorUnits: 10000, isAvailable: true, modifierGroups: [], channelPriceOverrides: {},
  });
}

async function bootstrapRealAdmin(organizationId: string): Promise<{ uid: string; idToken: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  const bootstrap = await callCallable(BOOTSTRAP_URL, { organizationId }, idToken);
  assert.strictEqual(bootstrap.httpStatus, 200, JSON.stringify(bootstrap.body));
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  return { uid, idToken: await refreshIdToken(refreshToken) };
}
async function newStaffMember(organizationId: string, branchId: string, adminIdToken: string, role: string) {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await db().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles: [role], branchAccess: [], restaurantAccess: [], status: "active", version: 1,
  });
  const assign = await callCallable(ASSIGN_ROLE_URL, { organizationId, targetUid: uid, role }, adminIdToken);
  assert.strictEqual(assign.httpStatus, 200, JSON.stringify(assign.body));
  const grantBranch = await callCallable(GRANT_BRANCH_URL, { organizationId, targetUid: uid, branchId }, adminIdToken);
  assert.strictEqual(grantBranch.httpStatus, 200, JSON.stringify(grantBranch.body));
  await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  return { uid, idToken: await refreshIdToken(refreshToken) };
}

/** Mirrors `dineInCanonicalLifecycle.test.ts`'s own `seedGuestAtTable`
 * (itself mirroring `ap3E2E.test.ts`'s) shape exactly. */
async function seedGuestAtTable(
  chain: { organizationId: string; restaurantId: string; branchId: string },
  tableId: string,
  guestAuthUid: string,
): Promise<{ guestSessionId: string; tableSessionId: string }> {
  const tableSessionId = nextId("tsess");
  await db().collection("restaurantTables").doc(tableId).set({
    organizationId: chain.organizationId, restaurantId: chain.restaurantId, branchId: chain.branchId,
    activeTableSessionId: tableSessionId, isActive: true, status: "occupied", displayName: "Masa 9",
  }, { merge: true });
  await db().collection("tableSessions").doc(tableSessionId).set({
    organizationId: chain.organizationId, restaurantId: chain.restaurantId, branchId: chain.branchId, tableId,
    status: "active", openedAt: admin.firestore.Timestamp.now(), closedAt: null,
    openedByType: "guestQrScan", openedByStaffUid: null, transferredFromTableId: null, version: 1,
  });
  const guestSessionId = nextId("tgs");
  await db().collection("tableGuestSessions").doc(guestSessionId).set({
    organizationId: chain.organizationId, restaurantId: chain.restaurantId, branchId: chain.branchId, tableId, tableSessionId,
    guestAuthUid, status: "active", createdAt: admin.firestore.Timestamp.now(),
    expiresAt: admin.firestore.Timestamp.fromDate(new Date(Date.now() + 6 * 60 * 60 * 1000)),
    lastActivityAt: admin.firestore.Timestamp.now(), qrTokenId: nextId("qrtoken"), reservationContextId: null,
  });
  const subAccountId = `subaccount-${tableSessionId}-${guestAuthUid}`;
  await db().collection("guestSubAccounts").doc(subAccountId).set({
    organizationId: chain.organizationId, branchId: chain.branchId, tableSessionId,
    ownerType: "guestSession", ownerSessionRef: `tableGuestSessions/${guestSessionId}`, ownerAuthUid: guestAuthUid,
    displayName: `Guest ${guestAuthUid.slice(0, 6)}`, status: "open", createdAt: admin.firestore.Timestamp.now(),
    createdByStaffUid: null, version: 1,
  });
  return { guestSessionId, tableSessionId };
}

test("dine-in guest order -> real staff accept -> a kitchenWorkItems doc is created with the right station and branch", async () => {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");

  const product = nextId("product");
  await seedMenuProductWithStation(product, restaurantId, organizationId, nextId("category"), "hot");

  const tableId = nextId("table");
  const guestAuth = await signUpAnonymously();
  const { guestSessionId } = await seedGuestAtTable({ organizationId, restaurantId, branchId }, tableId, guestAuth.uid);

  // The real anonymous-auth guest submits the order — exercises
  // `submitDineInOrder`'s own guestAuthUid/table-session ownership checks,
  // not an Admin-SDK-seeded order.
  const order = await callCallable(SUBMIT_DINE_IN_URL, {
    mode: "guestSession", submissionKey: nextId("key"), tableSessionId: guestSessionId,
    items: [{ kind: "product", productId: product, quantity: 2 }],
    guestDisplayName: "Ayşe",
  }, guestAuth.idToken);
  assert.strictEqual(order.httpStatus, 200, JSON.stringify(order.body));
  const orderId = order.body.result!.orderId as string;
  assert.strictEqual(order.body.result!.mode, "guestSession");

  // The real staff member accepts it — exercises `respondToDineInOrderLines`'
  // own `manageDineInOrders` permission + branch-access checks, via the real
  // membership/role-grant pipeline (`assignStaffRole`/`grantStaffBranchAccess`
  // /`syncOwnStaffClaims`), not a directly-minted custom claim.
  const acceptLines = await callCallable(RESPOND_LINES_URL, {
    orderId, decisions: [{ lineIndex: 0, decision: "accept" }],
  }, staff.idToken);
  assert.strictEqual(acceptLines.httpStatus, 200, JSON.stringify(acceptLines.body));

  const workItemId = `kwi-kt-${orderId}-line-0`;
  const workItem = await db().collection("kitchenWorkItems").doc(workItemId).get();
  assert.ok(workItem.exists, "acceptance must create a real kitchenWorkItems doc for the guest's line");
  const data = workItem.data()!;
  assert.strictEqual(data.orderId, orderId);
  assert.strictEqual(data.branchId, branchId);
  assert.strictEqual(data.station, "hot", "the product's real menuCategories.defaultStation must be used, not the shared fallback");
  assert.strictEqual(data.status, "queued");
  assert.strictEqual(data.quantity, 2);
});
