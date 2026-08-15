import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `provisionOrganization`/`provisionRestaurant`/
 * `provisionBranch` — Faz D.1 (Canonical Restaurant/Branch Provisioning)
 * and Faz D.1.1 (Canonical Organization Provisioning, closing Faz D.1's
 * one REQUIRED finding: `provisionRestaurant` now verifies its parent
 * `organizations/{organizationId}` document server-side instead of
 * trusting the caller's `organizationId` string alone). Run via
 * `npm run test:emulator`. Follows `tableGuestSession.test.ts`/
 * `processAccountDeletion.test.ts`'s exact pattern: raw HTTP against the
 * callable-functions wire protocol, no `firebase` client SDK dependency.
 *
 * All three functions require a `platformRole` custom claim
 * (`platformOwner`/`platformAdministrator`) — the Auth emulator does not
 * apply a freshly `setCustomUserClaims`'d claim to an already-issued
 * `idToken`; [mintPlatformOwnerIdToken]/[mintPlatformAdministratorIdToken]
 * sign up anonymously, set the claim via the Admin SDK, then exchange the
 * sign-up's `refreshToken` for a *new* `idToken` (via the Auth emulator's
 * `securetoken.googleapis.com` token endpoint) that actually carries it —
 * the same two-step dance any real client doing a claims-dependent
 * re-auth would need.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const PROVISION_ORGANIZATION_URL =
  `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/provisionOrganization`;
const PROVISION_RESTAURANT_URL =
  `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/provisionRestaurant`;
const PROVISION_BRANCH_URL =
  `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/provisionBranch`;

let app: admin.app.App;

before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});

after(async () => {
  await app.delete();
});

async function callCallable(
  url: string,
  data: Record<string, unknown>,
  idToken?: string,
) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, {
    method: "POST",
    headers,
    body: JSON.stringify({ data }),
  });
  const body = (await response.json()) as {
    result?: Record<string, unknown>;
    error?: { status?: string; message?: string };
  };
  return { httpStatus: response.status, body };
}

async function signUpAnonymously(): Promise<{
  idToken: string;
  refreshToken: string;
  uid: string;
}> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const body = (await response.json()) as {
    idToken: string;
    refreshToken: string;
    localId: string;
  };
  assert.strictEqual(response.status, 200, "Auth emulator sign-up must succeed");
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}

async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(
    `${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({
        grant_type: "refresh_token",
        refresh_token: refreshToken,
      }).toString(),
    },
  );
  const body = (await response.json()) as { id_token: string };
  assert.strictEqual(response.status, 200, "Auth emulator token refresh must succeed");
  return body.id_token;
}

/** A fresh anonymous user, promoted to `platformOwner`, with an idToken that actually carries the claim. */
async function mintPlatformOwnerIdToken(): Promise<string> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, { platformRole: "platformOwner" });
  return refreshIdToken(refreshToken);
}

/** Same as above, but `platformAdministrator` — the other role `requirePlatformMember` accepts. */
async function mintPlatformAdministratorIdToken(): Promise<string> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, { platformRole: "platformAdministrator" });
  return refreshIdToken(refreshToken);
}

/**
 * A fresh anonymous user promoted to a real *tenant*-level admin —
 * `organizationAccess`/`roles` claims shaped exactly like
 * `firestore.rules`'s own `isOrgMember`/`hasRole` expect, but with no
 * `platformRole` claim at all. Proves tenant-level authority (however
 * senior within its own tenant) never satisfies platform-level
 * provisioning authorization — a distinct negative case from "no claim at
 * all" ([mintPlainIdToken]).
 */
async function mintTenantAdminIdToken(): Promise<string> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, {
    organizationAccess: ["org-1"],
    roles: { "org-1": ["tenantOwner"] },
  });
  return refreshIdToken(refreshToken);
}

/** A fresh, plain anonymous user with no platform claim at all — the "ordinary technical identity" negative case. */
async function mintPlainIdToken(): Promise<string> {
  const { idToken } = await signUpAnonymously();
  return idToken;
}

// Faz R.1C.1.1 — a per-file random namespace so these ids can never collide
// with another test file's identically-numbered `test-org-N`/etc. — closing
// the same class of shared-emulator-state leakage root-caused in
// `respondToReservation.test.ts` (see that file's own comment for the full
// story: two files' counters both starting at 0 could silently share the
// same Firestore document).
const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;

let organizationCounter = 0;
function nextOrganizationId(): string {
  organizationCounter += 1;
  return `test-org-${TEST_RUN_ID}-${organizationCounter}`;
}
let restaurantCounter = 0;
function nextRestaurantId(): string {
  restaurantCounter += 1;
  return `test-restaurant-${TEST_RUN_ID}-${restaurantCounter}`;
}
let branchCounter = 0;
function nextBranchId(): string {
  branchCounter += 1;
  return `test-branch-${TEST_RUN_ID}-${branchCounter}`;
}

/** Provisions a fresh, active organization and returns its id — the standard setup step every restaurant/branch test below needs now that `provisionRestaurant` verifies its parent organization (Faz D.1.1). */
async function provisionOrg(
  token: string,
  overrides: Partial<{ organizationId: string; name: string; isActive: boolean }> = {},
): Promise<string> {
  const organizationId = overrides.organizationId ?? nextOrganizationId();
  const { body } = await callCallable(
    PROVISION_ORGANIZATION_URL,
    { organizationId, name: overrides.name ?? "Test Org", isActive: overrides.isActive },
    token,
  );
  assert.strictEqual(body.result?.organizationId, organizationId, "org setup step must succeed");
  return organizationId;
}

// ---------------------------------------------------------------------
// provisionOrganization
// ---------------------------------------------------------------------

test("provisionOrganization: a platform owner provisions a valid organization — canonical document created", async () => {
  const token = await mintPlatformOwnerIdToken();
  const organizationId = nextOrganizationId();

  const { httpStatus, body } = await callCallable(
    PROVISION_ORGANIZATION_URL,
    { organizationId, name: "Abaküs Test" },
    token,
  );

  assert.strictEqual(httpStatus, 200);
  assert.deepStrictEqual(body.result, { organizationId, created: true });

  const doc = await admin.firestore().collection("organizations").doc(organizationId).get();
  assert.ok(doc.exists);
  const data = doc.data()!;
  assert.strictEqual(data.name, "Abaküs Test");
  assert.strictEqual(data.isActive, true);
  assert.strictEqual(data.revision, 1);
  assert.ok(data.createdAt);
});

test("provisionOrganization: a platform administrator (not just owner) may also provision an organization", async () => {
  const token = await mintPlatformAdministratorIdToken();
  const organizationId = nextOrganizationId();

  const { httpStatus, body } = await callCallable(
    PROVISION_ORGANIZATION_URL,
    { organizationId, name: "Abaküs Test" },
    token,
  );

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.created, true);
});

test("provisionOrganization: an unauthenticated caller is rejected and no document is created", async () => {
  const organizationId = nextOrganizationId();

  const { httpStatus, body } = await callCallable(PROVISION_ORGANIZATION_URL, {
    organizationId,
    name: "Abaküs Test",
  });

  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
  const doc = await admin.firestore().collection("organizations").doc(organizationId).get();
  assert.strictEqual(doc.exists, false);
});

test("provisionOrganization: a real tenant-level admin (organizationAccess/roles claims, no platformRole) is rejected — tenant authority never satisfies platform authorization", async () => {
  const token = await mintTenantAdminIdToken();
  const organizationId = nextOrganizationId();

  const { httpStatus, body } = await callCallable(
    PROVISION_ORGANIZATION_URL,
    { organizationId, name: "Abaküs Test" },
    token,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
  const doc = await admin.firestore().collection("organizations").doc(organizationId).get();
  assert.strictEqual(doc.exists, false);
});

test("provisionOrganization: a signed-in caller with no platformRole claim at all is rejected", async () => {
  const token = await mintPlainIdToken();
  const organizationId = nextOrganizationId();

  const { httpStatus, body } = await callCallable(
    PROVISION_ORGANIZATION_URL,
    { organizationId, name: "Abaküs Test" },
    token,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
  const doc = await admin.firestore().collection("organizations").doc(organizationId).get();
  assert.strictEqual(doc.exists, false);
});

test("provisionOrganization: calling it twice with the same organizationId upserts the same single document — no duplicate, idempotent", async () => {
  const token = await mintPlatformOwnerIdToken();
  const organizationId = nextOrganizationId();

  const first = await callCallable(
    PROVISION_ORGANIZATION_URL,
    { organizationId, name: "Abaküs Test" },
    token,
  );
  const second = await callCallable(
    PROVISION_ORGANIZATION_URL,
    { organizationId, name: "Abaküs Test Renamed" },
    token,
  );

  assert.strictEqual(first.body.result?.created, true);
  assert.strictEqual(second.body.result?.created, false);

  const doc = await admin.firestore().collection("organizations").doc(organizationId).get();
  const data = doc.data()!;
  assert.strictEqual(data.name, "Abaküs Test Renamed");
  assert.strictEqual(data.revision, 2);
});

test("provisionOrganization: missing required fields are rejected with invalid-argument", async () => {
  const token = await mintPlatformOwnerIdToken();

  const missingId = await callCallable(PROVISION_ORGANIZATION_URL, { name: "Abaküs Test" }, token);
  const missingName = await callCallable(
    PROVISION_ORGANIZATION_URL,
    { organizationId: nextOrganizationId() },
    token,
  );

  assert.strictEqual(missingId.body.error?.status, "INVALID_ARGUMENT");
  assert.strictEqual(missingName.body.error?.status, "INVALID_ARGUMENT");
});

// ---------------------------------------------------------------------
// provisionRestaurant
// ---------------------------------------------------------------------

test("provisionRestaurant: a platform owner provisions a valid restaurant under an already-provisioned, active organization — canonical document created", async () => {
  const token = await mintPlatformOwnerIdToken();
  const organizationId = await provisionOrg(token);
  const restaurantId = nextRestaurantId();

  const { httpStatus, body } = await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId, restaurantId, name: "Abaküs Test" },
    token,
  );

  assert.strictEqual(httpStatus, 200);
  assert.deepStrictEqual(body.result, { restaurantId, organizationId, created: true });

  const doc = await admin.firestore().collection("restaurants").doc(restaurantId).get();
  assert.ok(doc.exists);
  const data = doc.data()!;
  assert.strictEqual(data.organizationId, organizationId);
  assert.strictEqual(data.name, "Abaküs Test");
  assert.strictEqual(data.isActive, true);
  assert.strictEqual(data.revision, 1);
  assert.ok(data.createdAt);
});

test("provisionRestaurant: a restaurant claiming an organization that was never provisioned is rejected — no document is created (missing parent)", async () => {
  const token = await mintPlatformOwnerIdToken();
  const restaurantId = nextRestaurantId();

  const { httpStatus, body } = await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId: "organization-that-does-not-exist", restaurantId, name: "Abaküs Test" },
    token,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const doc = await admin.firestore().collection("restaurants").doc(restaurantId).get();
  assert.strictEqual(doc.exists, false);
});

test("provisionRestaurant: a restaurant claiming a real but inactive organization is rejected — no document is created", async () => {
  const token = await mintPlatformOwnerIdToken();
  const organizationId = await provisionOrg(token, { isActive: false });
  const restaurantId = nextRestaurantId();

  const { httpStatus, body } = await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId, restaurantId, name: "Abaküs Test" },
    token,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const doc = await admin.firestore().collection("restaurants").doc(restaurantId).get();
  assert.strictEqual(doc.exists, false);
});

test("provisionRestaurant: calling it twice with identical data upserts the same single document — no duplicate, idempotent", async () => {
  const token = await mintPlatformOwnerIdToken();
  const organizationId = await provisionOrg(token);
  const restaurantId = nextRestaurantId();

  const first = await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId, restaurantId, name: "Abaküs Test" },
    token,
  );
  const second = await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId, restaurantId, name: "Abaküs Test Renamed" },
    token,
  );

  assert.strictEqual(first.body.result?.created, true);
  assert.strictEqual(second.body.result?.created, false);

  const doc = await admin.firestore().collection("restaurants").doc(restaurantId).get();
  const data = doc.data()!;
  assert.strictEqual(data.name, "Abaküs Test Renamed");
  assert.strictEqual(data.revision, 2);
  // Still exactly one document at this id — Firestore's own doc-id
  // semantics guarantee this structurally, this assertion documents why.
});

test("provisionRestaurant: re-provisioning an existing restaurant under a different (also real, active) organization is rejected — immutable tenant binding, cross-tenant reassignment attempt", async () => {
  const token = await mintPlatformOwnerIdToken();
  const organizationA = await provisionOrg(token);
  const organizationB = await provisionOrg(token);
  const restaurantId = nextRestaurantId();

  await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId: organizationA, restaurantId, name: "Abaküs Test" },
    token,
  );
  const { httpStatus, body } = await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId: organizationB, restaurantId, name: "Abaküs Test" },
    token,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");

  const doc = await admin.firestore().collection("restaurants").doc(restaurantId).get();
  assert.strictEqual(doc.data()!.organizationId, organizationA, "original binding must be untouched");
});

test("provisionRestaurant: an unauthenticated caller is rejected and no document is created", async () => {
  const restaurantId = nextRestaurantId();

  const { httpStatus, body } = await callCallable(PROVISION_RESTAURANT_URL, {
    organizationId: "org-irrelevant",
    restaurantId,
    name: "Abaküs Test",
  });

  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
  const doc = await admin.firestore().collection("restaurants").doc(restaurantId).get();
  assert.strictEqual(doc.exists, false);
});

test("provisionRestaurant: a signed-in caller with no platformRole claim is rejected — ordinary technical/customer identity cannot provision tenants", async () => {
  const token = await mintPlainIdToken();
  const restaurantId = nextRestaurantId();

  const { httpStatus, body } = await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId: "org-irrelevant", restaurantId, name: "Abaküs Test" },
    token,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
  const doc = await admin.firestore().collection("restaurants").doc(restaurantId).get();
  assert.strictEqual(doc.exists, false);
});

test("provisionRestaurant: a real tenant-level admin (organizationAccess/roles claims, no platformRole) is rejected", async () => {
  const token = await mintTenantAdminIdToken();
  const restaurantId = nextRestaurantId();

  const { httpStatus, body } = await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId: "org-1", restaurantId, name: "Abaküs Test" },
    token,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
  const doc = await admin.firestore().collection("restaurants").doc(restaurantId).get();
  assert.strictEqual(doc.exists, false);
});

test("provisionRestaurant: missing required fields are rejected with invalid-argument", async () => {
  const token = await mintPlatformOwnerIdToken();

  const missingOrg = await callCallable(
    PROVISION_RESTAURANT_URL,
    { restaurantId: nextRestaurantId(), name: "Abaküs Test" },
    token,
  );
  const missingName = await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId: "org-irrelevant", restaurantId: nextRestaurantId() },
    token,
  );

  assert.strictEqual(missingOrg.body.error?.status, "INVALID_ARGUMENT");
  assert.strictEqual(missingName.body.error?.status, "INVALID_ARGUMENT");
});

// ---------------------------------------------------------------------
// provisionBranch
// ---------------------------------------------------------------------

test("provisionBranch: a platform owner provisions a valid branch under an already-provisioned restaurant — canonical document created", async () => {
  const token = await mintPlatformOwnerIdToken();
  const organizationId = await provisionOrg(token);
  const restaurantId = nextRestaurantId();
  const branchId = nextBranchId();

  await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId, restaurantId, name: "Abaküs Test" },
    token,
  );
  const { httpStatus, body } = await callCallable(
    PROVISION_BRANCH_URL,
    {
      organizationId,
      restaurantId,
      branchId,
      name: "Merkez Şube",
      supportedOrderChannelIds: ["dineInQr", "dineInStaff", "delivery", "takeaway"],
    },
    token,
  );

  assert.strictEqual(httpStatus, 200);
  assert.deepStrictEqual(body.result, { branchId, restaurantId, organizationId, created: true });

  const doc = await admin.firestore().collection("branches").doc(branchId).get();
  assert.ok(doc.exists);
  const data = doc.data()!;
  assert.strictEqual(data.organizationId, organizationId);
  assert.strictEqual(data.restaurantId, restaurantId);
  assert.strictEqual(data.name, "Merkez Şube");
  assert.deepStrictEqual(data.supportedOrderChannelIds, [
    "dineInQr",
    "dineInStaff",
    "delivery",
    "takeaway",
  ]);
  assert.strictEqual(data.status, "active");
  assert.strictEqual(data.emergencyStopped, false);
  assert.strictEqual(data.revision, 1);
});

test("provisionBranch: a missing parent restaurant is rejected — no branch document is created (invalid/missing parent)", async () => {
  const token = await mintPlatformOwnerIdToken();
  const organizationId = await provisionOrg(token);
  const branchId = nextBranchId();

  const { httpStatus, body } = await callCallable(
    PROVISION_BRANCH_URL,
    {
      organizationId,
      restaurantId: "restaurant-that-does-not-exist",
      branchId,
      name: "Merkez Şube",
    },
    token,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const doc = await admin.firestore().collection("branches").doc(branchId).get();
  assert.strictEqual(doc.exists, false);
});

test("provisionBranch: a branch claiming an organizationId that does not match its parent restaurant's real organizationId is rejected — cross-tenant attempt (the claimed organization is itself real and active, only mismatched)", async () => {
  const token = await mintPlatformOwnerIdToken();
  const organizationReal = await provisionOrg(token);
  const organizationAttacker = await provisionOrg(token);
  const restaurantId = nextRestaurantId();
  const branchId = nextBranchId();

  await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId: organizationReal, restaurantId, name: "Abaküs Test" },
    token,
  );
  const { httpStatus, body } = await callCallable(
    PROVISION_BRANCH_URL,
    {
      organizationId: organizationAttacker,
      restaurantId,
      branchId,
      name: "Sahte Şube",
    },
    token,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const doc = await admin.firestore().collection("branches").doc(branchId).get();
  assert.strictEqual(doc.exists, false, "no branch document may exist for a rejected cross-tenant attempt");
});

test("provisionBranch: calling it twice with identical parent/org upserts the same single document — no duplicate, idempotent", async () => {
  const token = await mintPlatformOwnerIdToken();
  const organizationId = await provisionOrg(token);
  const restaurantId = nextRestaurantId();
  const branchId = nextBranchId();

  await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId, restaurantId, name: "Abaküs Test" },
    token,
  );
  const first = await callCallable(
    PROVISION_BRANCH_URL,
    { organizationId, restaurantId, branchId, name: "Merkez Şube" },
    token,
  );
  const second = await callCallable(
    PROVISION_BRANCH_URL,
    { organizationId, restaurantId, branchId, name: "Merkez Şube (güncellendi)" },
    token,
  );

  assert.strictEqual(first.body.result?.created, true);
  assert.strictEqual(second.body.result?.created, false);

  const doc = await admin.firestore().collection("branches").doc(branchId).get();
  const data = doc.data()!;
  assert.strictEqual(data.name, "Merkez Şube (güncellendi)");
  assert.strictEqual(data.revision, 2);
});

test("provisionBranch: re-provisioning an existing branch under a different restaurant is rejected (immutable parent binding)", async () => {
  const token = await mintPlatformOwnerIdToken();
  const organizationId = await provisionOrg(token);
  const restaurantA = nextRestaurantId();
  const restaurantB = nextRestaurantId();
  const branchId = nextBranchId();

  await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId, restaurantId: restaurantA, name: "A" },
    token,
  );
  await callCallable(
    PROVISION_RESTAURANT_URL,
    { organizationId, restaurantId: restaurantB, name: "B" },
    token,
  );
  await callCallable(
    PROVISION_BRANCH_URL,
    { organizationId, restaurantId: restaurantA, branchId, name: "Şube" },
    token,
  );

  const { httpStatus, body } = await callCallable(
    PROVISION_BRANCH_URL,
    { organizationId, restaurantId: restaurantB, branchId, name: "Şube" },
    token,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const doc = await admin.firestore().collection("branches").doc(branchId).get();
  assert.strictEqual(doc.data()!.restaurantId, restaurantA, "original parent binding must be untouched");
});

test("provisionBranch: an unauthenticated caller is rejected and no document is created", async () => {
  const restaurantId = nextRestaurantId();
  const branchId = nextBranchId();

  const { httpStatus, body } = await callCallable(PROVISION_BRANCH_URL, {
    organizationId: "org-irrelevant",
    restaurantId,
    branchId,
    name: "Şube",
  });

  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
  const doc = await admin.firestore().collection("branches").doc(branchId).get();
  assert.strictEqual(doc.exists, false);
});

test("provisionBranch: a signed-in caller with no platformRole claim is rejected", async () => {
  const token = await mintPlainIdToken();
  const restaurantId = nextRestaurantId();
  const branchId = nextBranchId();

  const { httpStatus, body } = await callCallable(
    PROVISION_BRANCH_URL,
    { organizationId: "org-irrelevant", restaurantId, branchId, name: "Şube" },
    token,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
  const doc = await admin.firestore().collection("branches").doc(branchId).get();
  assert.strictEqual(doc.exists, false);
});
