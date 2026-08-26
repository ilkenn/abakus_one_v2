import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for AP-2 Stage B's real `platformMembers` writer —
 * `syncOwnPlatformClaims`, `grantPlatformRole`, `revokePlatformRole`.
 * Mirrors `staffMembership.test.ts`'s exact harness one tier up (platform,
 * not tenant). The very first Platform Owner is deliberately NOT created
 * through any callable here — see `bootstrap_platform_owner.mjs` and its
 * own structural self-limiting test — these tests seed a platformMembers
 * document directly via Admin SDK to stand in for "bootstrap already ran."
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_PLATFORM_CLAIMS_URL = fn("syncOwnPlatformClaims");
const GRANT_PLATFORM_ROLE_URL = fn("grantPlatformRole");
const REVOKE_PLATFORM_ROLE_URL = fn("revokePlatformRole");

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

function decodeIdTokenClaims(idToken: string): Record<string, unknown> {
  const payload = idToken.split(".")[1];
  return JSON.parse(Buffer.from(payload, "base64").toString("utf8"));
}

/** Stands in for "bootstrap already ran" — seeds a platformMembers doc directly, mirroring bootstrap_platform_owner.mjs's own write shape. */
async function seedPlatformOwner(): Promise<{ uid: string; idToken: string; refreshToken: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await admin.firestore().collection("platformMembers").doc(uid).set({
    displayName: uid, roles: ["platformOwner"], status: "active", authUid: uid,
    createdAt: admin.firestore.Timestamp.now(), updatedAt: admin.firestore.Timestamp.now(), version: 1,
  });
  const sync = await callCallable(SYNC_PLATFORM_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  const refreshed = await refreshIdToken(refreshToken);
  return { uid, idToken: refreshed, refreshToken };
}

test("syncOwnPlatformClaims: an active platformMembers document yields the platformRole claim, holding the highest role", async () => {
  const { idToken } = await seedPlatformOwner();
  const claims = decodeIdTokenClaims(idToken);
  assert.strictEqual(claims.platformRole, "platformOwner");
});

test("syncOwnPlatformClaims: no platformMembers document yields a null claim, not an error", async () => {
  const { idToken, refreshToken } = await signUpAnonymously();
  const sync = await callCallable(SYNC_PLATFORM_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  const refreshed = await refreshIdToken(refreshToken);
  const claims = decodeIdTokenClaims(refreshed);
  assert.strictEqual(claims.platformRole, null);
});

test("grantPlatformRole: unauthenticated/non-platform caller is rejected", async () => {
  const { idToken: nonPlatformToken } = await signUpAnonymously();
  const { uid: targetUid } = await signUpAnonymously();
  const res = await callCallable(GRANT_PLATFORM_ROLE_URL, { targetUid, role: "platformAdministrator" }, nonPlatformToken);
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));

  const anon = await callCallable(GRANT_PLATFORM_ROLE_URL, { targetUid, role: "platformAdministrator" });
  assert.strictEqual(anon.httpStatus, 401, JSON.stringify(anon.body));
});

test("grantPlatformRole: a platform member cannot grant themselves a role", async () => {
  const owner = await seedPlatformOwner();
  const res = await callCallable(GRANT_PLATFORM_ROLE_URL, { targetUid: owner.uid, role: "platformAdministrator" }, owner.idToken);
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));
});

test("grantPlatformRole: a platformAdministrator cannot grant the platformOwner role — only an existing platformOwner may", async () => {
  const owner = await seedPlatformOwner();
  const { idToken: adminToken, uid: adminUid, refreshToken } = await signUpAnonymously();
  const grantAdmin = await callCallable(GRANT_PLATFORM_ROLE_URL, { targetUid: adminUid, role: "platformAdministrator" }, owner.idToken);
  assert.strictEqual(grantAdmin.httpStatus, 200, JSON.stringify(grantAdmin.body));
  await callCallable(SYNC_PLATFORM_CLAIMS_URL, {}, adminToken);
  const refreshedAdminToken = await refreshIdToken(refreshToken);

  const { uid: targetUid } = await signUpAnonymously();
  const res = await callCallable(GRANT_PLATFORM_ROLE_URL, { targetUid, role: "platformOwner" }, refreshedAdminToken);
  assert.strictEqual(res.httpStatus, 403, JSON.stringify(res.body));
});

test("grantPlatformRole: granting a role to a non-existent Firebase Auth uid is rejected", async () => {
  const owner = await seedPlatformOwner();
  const res = await callCallable(GRANT_PLATFORM_ROLE_URL, { targetUid: "no-such-uid-at-all", role: "platformAdministrator" }, owner.idToken);
  assert.strictEqual(res.httpStatus, 404, JSON.stringify(res.body));
});

test("grantPlatformRole + revokePlatformRole: full round trip, revoke is a no-op if the role was never held, self-revoke is rejected", async () => {
  const owner = await seedPlatformOwner();
  const { idToken: targetToken, uid: targetUid, refreshToken } = await signUpAnonymously();

  const grant = await callCallable(GRANT_PLATFORM_ROLE_URL, { targetUid, role: "platformAdministrator" }, owner.idToken);
  assert.strictEqual(grant.httpStatus, 200, JSON.stringify(grant.body));
  await callCallable(SYNC_PLATFORM_CLAIMS_URL, {}, targetToken);
  const refreshedTargetToken = await refreshIdToken(refreshToken);
  assert.strictEqual(decodeIdTokenClaims(refreshedTargetToken).platformRole, "platformAdministrator");

  const selfRevoke = await callCallable(REVOKE_PLATFORM_ROLE_URL, { targetUid, role: "platformAdministrator" }, refreshedTargetToken);
  assert.strictEqual(selfRevoke.httpStatus, 403, JSON.stringify(selfRevoke.body));

  const revoke = await callCallable(REVOKE_PLATFORM_ROLE_URL, { targetUid, role: "platformAdministrator" }, owner.idToken);
  assert.strictEqual(revoke.httpStatus, 200, JSON.stringify(revoke.body));
  assert.strictEqual(revoke.body.result?.revoked, true);

  const revokeAgain = await callCallable(REVOKE_PLATFORM_ROLE_URL, { targetUid, role: "platformAdministrator" }, owner.idToken);
  assert.strictEqual(revokeAgain.httpStatus, 200, JSON.stringify(revokeAgain.body));
  assert.strictEqual(revokeAgain.body.result?.revoked, false);
});

test("grantPlatformRole: every grant is recorded as an auditEvents entry with a backend-generated correlationId", async () => {
  const owner = await seedPlatformOwner();
  const { uid: targetUid } = await signUpAnonymously();
  const grant = await callCallable(GRANT_PLATFORM_ROLE_URL, { targetUid, role: "platformAdministrator", clientRequestId: "not-a-real-id-###" }, owner.idToken);
  assert.strictEqual(grant.httpStatus, 200, JSON.stringify(grant.body));
  const correlationId = grant.body.result?.correlationId as string;
  assert.ok(correlationId && correlationId.startsWith("corr_"));

  const eventDoc = await admin.firestore().collection("auditEvents").doc(`${targetUid}-platform-role-granted-platformAdministrator-v1`).get();
  assert.ok(eventDoc.exists);
  assert.strictEqual(eventDoc.data()?.type, "platform.roleGranted");
  assert.strictEqual(eventDoc.data()?.correlationId, correlationId);
  // The malformed client-supplied id must never be trusted/stored as-is.
  assert.strictEqual(eventDoc.data()?.clientRequestId, null);
});
