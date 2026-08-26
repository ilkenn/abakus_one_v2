import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { resolveVerifiedBranchContext } from "../tenantContext";
import type { CallableRequest } from "firebase-functions/v2/https";

/**
 * Emulator-backed tests for AP-2 Stage B's `resolveActorContext` callable —
 * Correction #2: a client-supplied organizationId/branchId is only ever an
 * untrusted locator, never authorization truth. Mirrors
 * `staffMembership.test.ts`'s harness.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const GRANT_BRANCH_URL = fn("grantStaffBranchAccess");
const RESOLVE_CONTEXT_URL = fn("resolveActorContext");

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
  await admin.firestore().collection("organizations").doc(organizationId).set({ name: "Test Org", isActive: true });
  await admin.firestore().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test Restaurant", isActive: true });
  await admin.firestore().collection("branches").doc(branchId).set({ restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false });
  return { organizationId, restaurantId, branchId };
}

async function bootstrapRealAdmin(organizationId: string): Promise<{ uid: string; idToken: string }> {
  const { idToken, uid, refreshToken } = await signUpAnonymously();
  const bootstrap = await callCallable(BOOTSTRAP_URL, { organizationId }, idToken);
  assert.strictEqual(bootstrap.httpStatus, 200, JSON.stringify(bootstrap.body));
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  // Custom claims only take effect on a freshly-issued token — the
  // pre-sync idToken above never reflects them (the bug this fixes: every
  // subsequent call in this file must use the REFRESHED token, mirroring
  // staffMembership.test.ts's own bootstrapRealAdmin exactly).
  const refreshed = await refreshIdToken(refreshToken);
  return { uid, idToken: refreshed };
}

test("resolveActorContext: unauthenticated caller is rejected", async () => {
  const res = await callCallable(RESOLVE_CONTEXT_URL, {});
  assert.strictEqual(res.httpStatus, 401, JSON.stringify(res.body));
});

test("resolveActorContext: returns exactly the caller's own active organizations/roles/branchIds, derived from Firestore, no client input accepted", async () => {
  const { organizationId, branchId } = await seedTenant();
  const { idToken, uid } = await bootstrapRealAdmin(organizationId);
  const grant = await callCallable(GRANT_BRANCH_URL, { organizationId, targetUid: uid, branchId }, idToken);
  assert.strictEqual(grant.httpStatus, 200, JSON.stringify(grant.body));

  // Client sends an unrelated organizationId in the payload — resolveActorContext
  // must ignore it entirely (it accepts no organizationId field at all).
  const res = await callCallable(RESOLVE_CONTEXT_URL, { organizationId: "some-other-org" }, idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  const orgs = res.body.result?.organizations as Array<{ organizationId: string; roles: string[]; branchIds: string[] }>;
  assert.strictEqual(orgs.length, 1);
  assert.strictEqual(orgs[0].organizationId, organizationId);
  assert.deepStrictEqual(orgs[0].roles, ["admin"]);
});

test("resolveActorContext: a caller with zero memberships gets an empty list, not an error", async () => {
  const { idToken } = await signUpAnonymously();
  const res = await callCallable(RESOLVE_CONTEXT_URL, {}, idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  assert.deepStrictEqual(res.body.result?.organizations, []);
});

test("resolveActorContext: a suspended membership is excluded from the returned context", async () => {
  const { organizationId } = await seedTenant();
  const { uid, idToken } = await bootstrapRealAdmin(organizationId);
  await admin.firestore().collection("memberships").doc(`${organizationId}_${uid}`).update({ status: "suspended" });

  const res = await callCallable(RESOLVE_CONTEXT_URL, {}, idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  assert.deepStrictEqual(res.body.result?.organizations, []);
});

function fakeRequest(uid: string): CallableRequest {
  return { auth: { uid, token: {} } } as unknown as CallableRequest;
}

test("resolveVerifiedBranchContext: a locator naming an organization the caller has no membership for is rejected, never silently redirected", async () => {
  const { organizationId } = await seedTenant();
  const { uid } = await bootstrapRealAdmin(organizationId);
  await assert.rejects(
    () => resolveVerifiedBranchContext(fakeRequest(uid), { organizationId: "org-caller-has-no-membership-for", branchId: "whatever" }),
    /permission-denied|No membership exists/,
  );
});

test("resolveVerifiedBranchContext: a branchId the caller has no branchAccess for is rejected even within a real membership", async () => {
  const { organizationId, branchId } = await seedTenant();
  const { uid } = await bootstrapRealAdmin(organizationId);
  // Bootstrap admin starts with branchAccess: [] — see staffMembership.test.ts's documented invariant.
  await assert.rejects(
    () => resolveVerifiedBranchContext(fakeRequest(uid), { organizationId, branchId }),
    /permission-denied|No branch access/,
  );
});

test("resolveVerifiedBranchContext: succeeds and returns the verified chain when membership + branchAccess + branch ownership all agree", async () => {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const { uid, idToken } = await bootstrapRealAdmin(organizationId);
  const grant = await callCallable(GRANT_BRANCH_URL, { organizationId, targetUid: uid, branchId }, idToken);
  assert.strictEqual(grant.httpStatus, 200, JSON.stringify(grant.body));

  const context = await resolveVerifiedBranchContext(fakeRequest(uid), { organizationId, branchId });
  assert.strictEqual(context.organizationId, organizationId);
  assert.strictEqual(context.branchId, branchId);
  assert.strictEqual(context.restaurantId, restaurantId);
  assert.deepStrictEqual(context.roles, ["admin"]);
});

test("resolveVerifiedBranchContext: a branch that belongs to a different organization than the locator claims is rejected", async () => {
  const tenantA = await seedTenant();
  const tenantB = await seedTenant();
  const { uid, idToken } = await bootstrapRealAdmin(tenantA.organizationId);
  const grant = await callCallable(GRANT_BRANCH_URL, { organizationId: tenantA.organizationId, targetUid: uid, branchId: tenantA.branchId }, idToken);
  assert.strictEqual(grant.httpStatus, 200, JSON.stringify(grant.body));

  // Forged locator: caller's own real organizationId, but a branchId that
  // actually belongs to tenant B — must never resolve as if it were tenant A's.
  await assert.rejects(
    () => resolveVerifiedBranchContext(fakeRequest(uid), { organizationId: tenantA.organizationId, branchId: tenantB.branchId }),
    /permission-denied|No branch access/,
  );
});
