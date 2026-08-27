import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * AP-3 continuation — emulator-backed tests for the Customer Directory
 * backfill tooling (`functions/src/customerDirectoryBackfill.ts`). Every
 * customer/tenant-membership document here is seeded DIRECTLY via the
 * Admin SDK (bypassing `completeCustomerProfile`) to simulate a customer
 * who registered BEFORE the live Wave 3 projection write existed — that is
 * exactly the gap this tooling exists to fill. Requires
 * `CUSTOMER_PHONE_SEARCH_HMAC_SECRET` to be available via
 * `functions/.secret.local` (emulator-only, gitignored).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const BACKFILL_PLATFORM_URL = fn("runPlatformCustomerDirectoryBackfill");
const BACKFILL_TENANT_URL = fn("runTenantCustomerDirectoryBackfill");
const SYNC_PLATFORM_CLAIMS_URL = fn("syncOwnPlatformClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");

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
function nextId(prefix: string): string { idCounter += 1; return `${prefix}-${TEST_RUN_ID}-${idCounter}`; }

async function seedPlatformOwner(): Promise<{ uid: string; idToken: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await db().collection("platformMembers").doc(uid).set({
    displayName: uid, roles: ["platformOwner"], status: "active", authUid: uid,
    createdAt: admin.firestore.Timestamp.now(), updatedAt: admin.firestore.Timestamp.now(), version: 1,
  });
  const sync = await callCallable(SYNC_PLATFORM_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  return { uid, idToken: await refreshIdToken(refreshToken) };
}
async function seedTenant() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  await db().collection("branches").doc(branchId).set({ restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false });
  return { organizationId, restaurantId, branchId };
}
async function bootstrapRealAdmin(organizationId: string): Promise<{ uid: string; idToken: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  const bootstrap = await callCallable(BOOTSTRAP_URL, { organizationId }, idToken);
  assert.strictEqual(bootstrap.httpStatus, 200, JSON.stringify(bootstrap.body));
  return { uid, idToken: await refreshIdToken(refreshToken) };
}

/** Simulates a customer who completed registration BEFORE the Wave 3 projection write existed — a bare `customers/{uid}` doc with no corresponding `platformCustomerDirectoryEntries/{uid}`. */
async function seedRawCompleteCustomer(overrides: { firstName?: string; phoneNumber?: string; complete?: boolean } = {}) {
  const uid = nextId("legacycust");
  const now = admin.firestore.Timestamp.now();
  const phoneNumber = overrides.phoneNumber ?? `+1555${String(Math.floor(Math.random() * 900000) + 100000)}`;
  const firstName = overrides.firstName ?? "Legacy";
  const data: Record<string, unknown> = {
    uid, firstName, lastName: "Customer",
    displayName: `${firstName} Customer`,
    email: `${uid}@example.com`, phoneNumber,
    occupationStatus: "other", gender: "preferNotToSay",
    birthDate: "1990-01-01",
    accountStatus: "active", createdAt: now, updatedAt: now,
  };
  if (overrides.complete !== false) {
    data.profileCompletedAt = now;
  }
  await db().collection("customers").doc(uid).set(data);
  return { uid, phoneNumber, displayName: data.displayName as string };
}
async function seedRawTenantMembership(organizationId: string, uid: string) {
  await db().collection("tenantCustomers").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, createdAt: admin.firestore.Timestamp.now(),
  });
}

test("Platform backfill: dry run reports what WOULD be created, writes nothing", async () => {
  const owner = await seedPlatformOwner();
  const customer = await seedRawCompleteCustomer();

  const dry = await callCallable(BACKFILL_PLATFORM_URL, { dryRun: true }, owner.idToken);
  assert.strictEqual(dry.httpStatus, 200, JSON.stringify(dry.body));
  assert.strictEqual(dry.body.result?.dryRun, true);
  assert.ok((dry.body.result?.createdCount as number) >= 1);

  const projectionSnap = await db().collection("platformCustomerDirectoryEntries").doc(customer.uid).get();
  assert.strictEqual(projectionSnap.exists, false, "a dry run must never write anything");
});

test("Platform backfill: first run creates the missing projection; a second identical run is a pure no-op (idempotent, safe rerun)", async () => {
  const owner = await seedPlatformOwner();
  const customer = await seedRawCompleteCustomer();

  const first = await callCallable(BACKFILL_PLATFORM_URL, {}, owner.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));

  const projectionSnap = await db().collection("platformCustomerDirectoryEntries").doc(customer.uid).get();
  assert.strictEqual(projectionSnap.exists, true);
  const projection = projectionSnap.data()!;
  assert.strictEqual(projection.uid, customer.uid);
  assert.strictEqual(projection.displayName, customer.displayName);
  assert.strictEqual(typeof projection.phoneSearchHash, "string");
  assert.strictEqual(projection.phoneNumber, customer.phoneNumber);
  assert.strictEqual(projection.accountState, "active");
  const firstUpdatedAt = (projection.updatedAt as admin.firestore.Timestamp).toMillis();

  // Second, identical run: the target already exists, so it must be
  // skipped verbatim, never re-merged/re-timestamped and never duplicated.
  const second = await callCallable(BACKFILL_PLATFORM_URL, {}, owner.idToken);
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));

  const projectionAfterRerun = (await db().collection("platformCustomerDirectoryEntries").doc(customer.uid).get()).data()!;
  assert.strictEqual(
    (projectionAfterRerun.updatedAt as admin.firestore.Timestamp).toMillis(),
    firstUpdatedAt,
    "an already-existing projection must never be touched by a rerun",
  );
});

test("Platform backfill: an incomplete customer profile is skipped, never given a projection", async () => {
  const owner = await seedPlatformOwner();
  const incomplete = await seedRawCompleteCustomer({ complete: false });

  await callCallable(BACKFILL_PLATFORM_URL, {}, owner.idToken);

  const projectionSnap = await db().collection("platformCustomerDirectoryEntries").doc(incomplete.uid).get();
  assert.strictEqual(projectionSnap.exists, false);
});

test("Platform backfill: an interrupted/resumed run (small batches, following nextCursor) processes every gap exactly once, none duplicated", async () => {
  const owner = await seedPlatformOwner();
  const seeded = [await seedRawCompleteCustomer(), await seedRawCompleteCustomer(), await seedRawCompleteCustomer()];

  let cursor: string | null = null;
  let totalCreated = 0;
  let iterations = 0;
  do {
    const page: { httpStatus: number; body: { result?: Record<string, unknown> } } = await callCallable(
      BACKFILL_PLATFORM_URL,
      { batchSize: 1, cursor },
      owner.idToken,
    );
    assert.strictEqual(page.httpStatus, 200, JSON.stringify(page.body));
    totalCreated += page.body.result?.createdCount as number;
    cursor = page.body.result?.nextCursor as string | null;
    iterations += 1;
    assert.ok(iterations < 10_000, "runaway pagination loop — nextCursor never became null");
  } while (cursor !== null);

  assert.ok(totalCreated >= 3, `expected at least the 3 seeded gaps to be created, got ${totalCreated}`);
  for (const customer of seeded) {
    const projectionSnap = await db().collection("platformCustomerDirectoryEntries").doc(customer.uid).get();
    assert.strictEqual(projectionSnap.exists, true, `${customer.uid} should have been created across the resumed run`);
  }
});

test("Platform backfill: denied for a caller without the customerDirectory.runBackfill capability", async () => {
  const { organizationId } = await seedTenant();
  const tenantAdmin = await bootstrapRealAdmin(organizationId);
  const denied = await callCallable(BACKFILL_PLATFORM_URL, {}, tenantAdmin.idToken);
  assert.strictEqual(denied.httpStatus, 403, JSON.stringify(denied.body));
});

test("Platform backfill: denied for an unauthenticated caller", async () => {
  const denied = await callCallable(BACKFILL_PLATFORM_URL, {});
  assert.strictEqual(denied.httpStatus, 401, JSON.stringify(denied.body));
});

test("Tenant backfill: first run creates the missing tenant projection from canonical tenantCustomers evidence; second identical run is a no-op", async () => {
  const owner = await seedPlatformOwner();
  const { organizationId } = await seedTenant();
  const customer = await seedRawCompleteCustomer();
  await seedRawTenantMembership(organizationId, customer.uid);

  const first = await callCallable(BACKFILL_TENANT_URL, {}, owner.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));

  const entryId = `${organizationId}_${customer.uid}`;
  const entrySnap = await db().collection("customerDirectoryEntries").doc(entryId).get();
  assert.strictEqual(entrySnap.exists, true);
  const entry = entrySnap.data()!;
  assert.strictEqual(entry.organizationId, organizationId);
  assert.strictEqual(entry.customerId, customer.uid);
  assert.strictEqual(entry.displayName, customer.displayName);
  assert.strictEqual(entry.totalOrderCount, 0);
  const firstUpdatedAt = (entry.updatedAt as admin.firestore.Timestamp).toMillis();

  const second = await callCallable(BACKFILL_TENANT_URL, {}, owner.idToken);
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  const entryAfterRerun = (await db().collection("customerDirectoryEntries").doc(entryId).get()).data()!;
  assert.strictEqual(
    (entryAfterRerun.updatedAt as admin.firestore.Timestamp).toMillis(),
    firstUpdatedAt,
    "an already-existing tenant projection must never be touched by a rerun",
  );
});

test("Tenant backfill: cross-tenant isolation — each membership's own organizationId is used, never a caller-supplied one, so two orgs never collide", async () => {
  const owner = await seedPlatformOwner();
  const orgA = await seedTenant();
  const orgB = await seedTenant();
  const customerA = await seedRawCompleteCustomer();
  const customerB = await seedRawCompleteCustomer();
  await seedRawTenantMembership(orgA.organizationId, customerA.uid);
  await seedRawTenantMembership(orgB.organizationId, customerB.uid);

  let cursor: string | null = null;
  do {
    const page: { httpStatus: number; body: { result?: Record<string, unknown> } } = await callCallable(
      BACKFILL_TENANT_URL,
      { batchSize: 1, cursor },
      owner.idToken,
    );
    assert.strictEqual(page.httpStatus, 200, JSON.stringify(page.body));
    cursor = page.body.result?.nextCursor as string | null;
  } while (cursor !== null);

  const entryA = (await db().collection("customerDirectoryEntries").doc(`${orgA.organizationId}_${customerA.uid}`).get()).data();
  const entryB = (await db().collection("customerDirectoryEntries").doc(`${orgB.organizationId}_${customerB.uid}`).get()).data();
  assert.strictEqual(entryA?.organizationId, orgA.organizationId);
  assert.strictEqual(entryB?.organizationId, orgB.organizationId);
  // Neither customer's projection was created under the OTHER org.
  const crossA = await db().collection("customerDirectoryEntries").doc(`${orgB.organizationId}_${customerA.uid}`).get();
  const crossB = await db().collection("customerDirectoryEntries").doc(`${orgA.organizationId}_${customerB.uid}`).get();
  assert.strictEqual(crossA.exists, false);
  assert.strictEqual(crossB.exists, false);
});

test("Tenant backfill: a membership whose customer profile is missing/incomplete is skipped, not given a projection", async () => {
  const owner = await seedPlatformOwner();
  const { organizationId } = await seedTenant();
  const incomplete = await seedRawCompleteCustomer({ complete: false });
  await seedRawTenantMembership(organizationId, incomplete.uid);

  await callCallable(BACKFILL_TENANT_URL, {}, owner.idToken);

  const entrySnap = await db().collection("customerDirectoryEntries").doc(`${organizationId}_${incomplete.uid}`).get();
  assert.strictEqual(entrySnap.exists, false);
});

test("Tenant backfill: denied for a caller without the customerDirectory.runBackfill capability", async () => {
  const { organizationId } = await seedTenant();
  const tenantAdmin = await bootstrapRealAdmin(organizationId);
  const denied = await callCallable(BACKFILL_TENANT_URL, {}, tenantAdmin.idToken);
  assert.strictEqual(denied.httpStatus, 403, JSON.stringify(denied.body));
});
