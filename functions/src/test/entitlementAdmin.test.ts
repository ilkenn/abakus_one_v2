import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for AP-2 Stage B's real `entitlements` writer —
 * `grantEntitlement`/`renewEntitlement`/`suspendEntitlement`/
 * `revokeEntitlement`/`sweepExpiredEntitlementGracePeriods`. Mirrors
 * `staffMembership.test.ts`'s harness one tier up (platform, not tenant —
 * every callable here is Platform-Owner/Administrator-gated, exactly like
 * `platformMembership.test.ts`).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_PLATFORM_CLAIMS_URL = fn("syncOwnPlatformClaims");
const GRANT_ENTITLEMENT_URL = fn("grantEntitlement");
const RENEW_ENTITLEMENT_URL = fn("renewEntitlement");
const SUSPEND_ENTITLEMENT_URL = fn("suspendEntitlement");
const REVOKE_ENTITLEMENT_URL = fn("revokeEntitlement");
const SWEEP_GRACE_URL = fn("sweepExpiredEntitlementGracePeriods");

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

async function platformOwnerToken(): Promise<{ idToken: string; uid: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await admin.firestore().collection("platformMembers").doc(uid).set({
    displayName: uid, roles: ["platformOwner"], status: "active", authUid: uid,
    createdAt: admin.firestore.Timestamp.now(), updatedAt: admin.firestore.Timestamp.now(), version: 1,
  });
  const sync = await callCallable(SYNC_PLATFORM_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  return { idToken: await refreshIdToken(refreshToken), uid };
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

test("grantEntitlement: non-platform caller is rejected — tenant Admin cannot self-grant (no tenant-scoped path exists at all)", async () => {
  const { idToken: nonPlatformToken } = await signUpAnonymously();
  const res = await callCallable(
    GRANT_ENTITLEMENT_URL,
    { organizationId: nextId("org"), scopeType: "organization", scopeId: "x", module: "pos" },
    nonPlatformToken,
  );
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));
});

test("grantEntitlement: creates a trial-status grant by default, idempotent on a second call for the same target", async () => {
  const owner = await platformOwnerToken();
  const organizationId = nextId("org");
  const res = await callCallable(
    GRANT_ENTITLEMENT_URL,
    { organizationId, scopeType: "organization", scopeId: organizationId, module: "pos" },
    owner.idToken,
  );
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  assert.strictEqual(res.body.result?.status, "trial");

  const again = await callCallable(
    GRANT_ENTITLEMENT_URL,
    { organizationId, scopeType: "organization", scopeId: organizationId, module: "pos" },
    owner.idToken,
  );
  assert.strictEqual(again.httpStatus, 200, JSON.stringify(again.body));
  assert.strictEqual(again.body.result?.alreadyGranted, true);
});

test("suspendEntitlement: always enters a grace period first — status becomes \"grace\", never an immediate hard suspend", async () => {
  const owner = await platformOwnerToken();
  const organizationId = nextId("org");
  const grant = await callCallable(
    GRANT_ENTITLEMENT_URL,
    { organizationId, scopeType: "organization", scopeId: organizationId, module: "kds", initialStatus: "active" },
    owner.idToken,
  );
  const entitlementId = grant.body.result?.entitlementId as string;

  const suspend = await callCallable(SUSPEND_ENTITLEMENT_URL, { entitlementId, reasonMessage: "non-payment" }, owner.idToken);
  assert.strictEqual(suspend.httpStatus, 200, JSON.stringify(suspend.body));
  assert.strictEqual(suspend.body.result?.status, "grace");

  const doc = await admin.firestore().collection("entitlements").doc(entitlementId).get();
  const graceStartedAt = (doc.data()?.graceStartedAt as admin.firestore.Timestamp).toMillis();
  const graceEndsAt = (doc.data()?.graceEndsAt as admin.firestore.Timestamp).toMillis();
  const THREE_DAYS_MS = 3 * 24 * 60 * 60 * 1000;
  assert.strictEqual(graceEndsAt - graceStartedAt, THREE_DAYS_MS);
  assert.deepStrictEqual(doc.data()?.postGraceDisabledModules, ["kds"]);
});

test("sweepExpiredEntitlementGracePeriods: a grace period past its end transitions to \"suspended\"", async () => {
  const owner = await platformOwnerToken();
  const organizationId = nextId("org");
  const grant = await callCallable(
    GRANT_ENTITLEMENT_URL,
    { organizationId, scopeType: "organization", scopeId: organizationId, module: "crm", initialStatus: "active" },
    owner.idToken,
  );
  const entitlementId = grant.body.result?.entitlementId as string;
  await callCallable(SUSPEND_ENTITLEMENT_URL, { entitlementId, reasonMessage: "non-payment" }, owner.idToken);

  await admin.firestore().collection("entitlements").doc(entitlementId).update({
    graceEndsAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000),
  });

  const sweep = await callCallable(SWEEP_GRACE_URL, {});
  assert.strictEqual(sweep.httpStatus, 200, JSON.stringify(sweep.body));
  assert.ok((sweep.body.result?.suspended as number) >= 1);

  const doc = await admin.firestore().collection("entitlements").doc(entitlementId).get();
  assert.strictEqual(doc.data()?.status, "suspended");
});

test("renewEntitlement: clears grace state and returns to \"active\"; a revoked entitlement cannot be renewed", async () => {
  const owner = await platformOwnerToken();
  const organizationId = nextId("org");
  const grant = await callCallable(
    GRANT_ENTITLEMENT_URL,
    { organizationId, scopeType: "organization", scopeId: organizationId, module: "loyalty", initialStatus: "active" },
    owner.idToken,
  );
  const entitlementId = grant.body.result?.entitlementId as string;
  await callCallable(SUSPEND_ENTITLEMENT_URL, { entitlementId, reasonMessage: "temp" }, owner.idToken);

  const renew = await callCallable(
    RENEW_ENTITLEMENT_URL,
    { entitlementId, contractEndsAtIso: new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString() },
    owner.idToken,
  );
  assert.strictEqual(renew.httpStatus, 200, JSON.stringify(renew.body));
  assert.strictEqual(renew.body.result?.status, "active");
  const doc = await admin.firestore().collection("entitlements").doc(entitlementId).get();
  assert.strictEqual(doc.data()?.graceStartedAt, null);
  assert.strictEqual(doc.data()?.graceEndsAt, null);

  const revoke = await callCallable(REVOKE_ENTITLEMENT_URL, { entitlementId, reasonMessage: "contract terminated" }, owner.idToken);
  assert.strictEqual(revoke.httpStatus, 200, JSON.stringify(revoke.body));
  const renewAfterRevoke = await callCallable(
    RENEW_ENTITLEMENT_URL,
    { entitlementId, contractEndsAtIso: new Date(Date.now() + 1000).toISOString() },
    owner.idToken,
  );
  assert.strictEqual(renewAfterRevoke.httpStatus, 400, JSON.stringify(renewAfterRevoke.body)); // failed-precondition
});

test("revokeEntitlement: immediate, terminal, idempotent on a second call", async () => {
  const owner = await platformOwnerToken();
  const organizationId = nextId("org");
  const grant = await callCallable(
    GRANT_ENTITLEMENT_URL,
    { organizationId, scopeType: "organization", scopeId: organizationId, module: "marketplace" },
    owner.idToken,
  );
  const entitlementId = grant.body.result?.entitlementId as string;

  const revoke = await callCallable(REVOKE_ENTITLEMENT_URL, { entitlementId, reasonMessage: "fraud" }, owner.idToken);
  assert.strictEqual(revoke.httpStatus, 200, JSON.stringify(revoke.body));
  assert.strictEqual(revoke.body.result?.alreadyRevoked, false);

  const revokeAgain = await callCallable(REVOKE_ENTITLEMENT_URL, { entitlementId, reasonMessage: "fraud (again)" }, owner.idToken);
  assert.strictEqual(revokeAgain.httpStatus, 200, JSON.stringify(revokeAgain.body));
  assert.strictEqual(revokeAgain.body.result?.alreadyRevoked, true);
});

test("every entitlement mutation is recorded as an auditEvents entry with a backend-generated correlationId", async () => {
  const owner = await platformOwnerToken();
  const organizationId = nextId("org");
  const grant = await callCallable(
    GRANT_ENTITLEMENT_URL,
    { organizationId, scopeType: "organization", scopeId: organizationId, module: "ai" },
    owner.idToken,
  );
  const entitlementId = grant.body.result?.entitlementId as string;
  const correlationId = grant.body.result?.correlationId as string;
  assert.ok(correlationId.startsWith("corr_"));

  const eventDoc = await admin.firestore().collection("auditEvents").doc(`${entitlementId}-granted-v1`).get();
  assert.ok(eventDoc.exists);
  assert.strictEqual(eventDoc.data()?.type, "entitlement.granted");
  assert.strictEqual(eventDoc.data()?.organizationId, organizationId);
});
