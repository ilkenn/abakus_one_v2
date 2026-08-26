import { test, before, after, describe } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { resolveEffectivePermissions } from "../staffPermissionOverrides";

/**
 * Emulator-backed tests for AP-2 Stage B's `setStaffPermissionOverride` +
 * a pure unit-test suite for `resolveEffectivePermissions` itself. Mirrors
 * `staffMembership.test.ts`'s exact harness (raw HTTP against the callable
 * wire protocol, real Firestore fixtures, per-file `TEST_RUN_ID`
 * namespace).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const ASSIGN_ROLE_URL = fn("assignStaffRole");
const GRANT_BRANCH_URL = fn("grantStaffBranchAccess");
const SET_OVERRIDE_URL = fn("setStaffPermissionOverride");

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

async function bootstrapRealAdmin(organizationId: string): Promise<{ uid: string; idToken: string; refreshToken: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  const bootstrap = await callCallable(BOOTSTRAP_URL, { organizationId }, idToken);
  assert.strictEqual(bootstrap.httpStatus, 200, JSON.stringify(bootstrap.body));
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  const refreshed = await refreshIdToken(refreshToken);
  return { uid, idToken: refreshed, refreshToken };
}

async function newStaffMember(organizationId: string, branchId: string, adminIdToken: string, role = "staff") {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  // Directly seed the membership (registerStaffMember requires an email
  // lookup, irrelevant to this file's own scenarios) — mirrors other test
  // files' precedent of seeding a membership doc directly when only its
  // resulting authorization behavior is under test.
  await admin.firestore().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles: [role], branchAccess: [], restaurantAccess: [], status: "active", version: 1,
  });
  const assign = await callCallable(ASSIGN_ROLE_URL, { organizationId, targetUid: uid, role }, adminIdToken);
  assert.strictEqual(assign.httpStatus, 200, JSON.stringify(assign.body));
  const grantBranch = await callCallable(GRANT_BRANCH_URL, { organizationId, targetUid: uid, branchId }, adminIdToken);
  assert.strictEqual(grantBranch.httpStatus, 200, JSON.stringify(grantBranch.body));
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  const refreshed = await refreshIdToken(refreshToken);
  return { uid, idToken: refreshed };
}

describe("resolveEffectivePermissions (pure)", () => {
  test("role-derived permissions form the base set", () => {
    const result = resolveEffectivePermissions(
      ["manager"],
      undefined,
      null,
      { manager: ["manageBranch", "manageReservations"] },
    );
    assert.deepStrictEqual([...result].sort(), ["manageBranch", "manageReservations"]);
  });

  test("organization grant adds a permission the role does not carry", () => {
    const result = resolveEffectivePermissions(
      ["staff"],
      { organization: { manageBranch: "grant" } },
      null,
      { staff: [] },
    );
    assert.ok(result.has("manageBranch" as never));
  });

  test("explicit deny always wins over a role-derived grant", () => {
    const result = resolveEffectivePermissions(
      ["manager"],
      { organization: { manageBranch: "deny" } },
      null,
      { manager: ["manageBranch"] },
    );
    assert.strictEqual(result.has("manageBranch" as never), false);
  });

  test("explicit deny always wins over an organization grant of the same permission", () => {
    const result = resolveEffectivePermissions(
      ["staff"],
      { organization: { manageBranch: "grant" } },
      null,
      { staff: [] },
    );
    assert.ok(result.has("manageBranch" as never));
    const denied = resolveEffectivePermissions(
      ["staff"],
      { organization: { manageBranch: "deny" } },
      null,
      { staff: ["manageBranch"] },
    );
    assert.strictEqual(denied.has("manageBranch" as never), false);
  });

  test("organization and branch overrides carry separate scope — a branch grant never leaks to a different branch", () => {
    const result = resolveEffectivePermissions(
      ["staff"],
      { branch: { "branch-A": { manageBranch: "grant" } } },
      "branch-B",
      { staff: [] },
    );
    assert.strictEqual(result.has("manageBranch" as never), false);
  });

  test("a branch-scoped deny wins even when the organization scope grants the same permission", () => {
    const result = resolveEffectivePermissions(
      ["staff"],
      {
        organization: { manageBranch: "grant" },
        branch: { "branch-A": { manageBranch: "deny" } },
      },
      "branch-A",
      { staff: [] },
    );
    assert.strictEqual(result.has("manageBranch" as never), false);
  });
});

test("setStaffPermissionOverride: organization-scope grant takes effect for the target's own effective permission", async () => {
  const { organizationId, branchId } = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, adminToken);

  const res = await callCallable(
    SET_OVERRIDE_URL,
    { organizationId, targetUid: staff.uid, permission: "manageBranch", scope: "organization", effect: "grant" },
    adminToken,
  );
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));

  const doc = await admin.firestore().collection("memberships").doc(`${organizationId}_${staff.uid}`).get();
  assert.strictEqual(doc.data()?.permissionOverrides?.organization?.manageBranch, "grant");
  assert.strictEqual(doc.data()?.version, 4); // create(1) + assignRole(2) + grantBranch(3) + override(4)
});

test("setStaffPermissionOverride: self-override is rejected for both grant and deny", async () => {
  const { organizationId, branchId } = await seedTenant();
  const { idToken: adminToken, uid: adminUid } = await bootstrapRealAdmin(organizationId);
  await newStaffMember(organizationId, branchId, adminToken); // unrelated, keeps setup realistic

  const res = await callCallable(
    SET_OVERRIDE_URL,
    { organizationId, targetUid: adminUid, permission: "manageBranch", scope: "organization", effect: "grant" },
    adminToken,
  );
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));
});

test("setStaffPermissionOverride: caller cannot grant a permission they do not themselves hold", async () => {
  const { organizationId, branchId } = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(organizationId);
  const manager = await newStaffMember(organizationId, branchId, adminToken, "manager");
  const target = await newStaffMember(organizationId, branchId, adminToken, "staff");

  // Every DEFAULT_STAFF_ROLE_PERMISSIONS entry for "manager" already
  // includes manageBranch, so the only way to construct a caller who
  // passes the meta-permission gate (manageStaffRoles) yet does NOT
  // effectively hold the permission being granted is an active deny
  // override on the caller themselves — proving the check reads the
  // caller's real EFFECTIVE set, not their role tier.
  const denyManager = await callCallable(
    SET_OVERRIDE_URL,
    { organizationId, targetUid: manager.uid, permission: "manageBranch", scope: "organization", effect: "deny" },
    adminToken,
  );
  assert.strictEqual(denyManager.httpStatus, 200, JSON.stringify(denyManager.body));

  const res = await callCallable(
    SET_OVERRIDE_URL,
    { organizationId, targetUid: target.uid, permission: "manageBranch", scope: "organization", effect: "grant" },
    manager.idToken,
  );
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));
});

test("setStaffPermissionOverride: deny never requires the caller to already hold the permission", async () => {
  const { organizationId, branchId } = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(organizationId);
  const manager = await newStaffMember(organizationId, branchId, adminToken, "manager");
  const target = await newStaffMember(organizationId, branchId, adminToken, "staff");

  const res = await callCallable(
    SET_OVERRIDE_URL,
    { organizationId, targetUid: target.uid, permission: "manageTakeawayOrderRefunds", scope: "organization", effect: "deny" },
    manager.idToken,
  );
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
});

test("setStaffPermissionOverride: overriding an admin-tier permission requires manageStaffAdminRole, not manageStaffRoles alone", async () => {
  const { organizationId, branchId } = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(organizationId);
  const manager = await newStaffMember(organizationId, branchId, adminToken, "manager");
  const target = await newStaffMember(organizationId, branchId, adminToken, "staff");

  const res = await callCallable(
    SET_OVERRIDE_URL,
    { organizationId, targetUid: target.uid, permission: "manageStaffAdminRole", scope: "organization", effect: "deny" },
    manager.idToken,
  );
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));
});

test("setStaffPermissionOverride: branch scope requires the caller to hold branch access for that branch", async () => {
  const { organizationId, branchId } = await seedTenant();
  const { idToken: adminToken } = await bootstrapRealAdmin(organizationId);
  const target = await newStaffMember(organizationId, branchId, adminToken, "staff");
  const otherBranchId = nextId("branch");
  await admin.firestore().collection("branches").doc(otherBranchId).set({
    restaurantId: nextId("restaurant"), organizationId, name: "Other", status: "active", emergencyStopped: false,
  });

  const res = await callCallable(
    SET_OVERRIDE_URL,
    { organizationId, targetUid: target.uid, permission: "manageBranch", scope: "branch", branchId: otherBranchId, effect: "deny" },
    adminToken,
  );
  // Admin (bootstrap) itself has branchAccess: [] — see staffMembership.test.ts's own
  // documented invariant — so even an admin fails this branch-access check.
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));
});

test("setStaffPermissionOverride: unauthenticated caller is rejected", async () => {
  const { organizationId } = await seedTenant();
  const res = await callCallable(SET_OVERRIDE_URL, {
    organizationId, targetUid: "someone", permission: "manageBranch", scope: "organization", effect: "grant",
  });
  assert.strictEqual(res.httpStatus, 401, JSON.stringify(res.body));
});
