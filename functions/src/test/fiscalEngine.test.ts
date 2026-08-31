import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * AP-4 Wave C — emulator-backed tests for the real fiscal operation
 * journal + offline authorization lease engine (`fiscalEngine.ts`). Reuses
 * the exact fixture pattern established by `cashRegisterEngine.test.ts`.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const ASSIGN_ROLE_URL = fn("assignStaffRole");
const GRANT_BRANCH_URL = fn("grantStaffBranchAccess");
const REQUEST_DEVICE_REGISTRATION_URL = fn("requestDeviceRegistration");
const REQUEST_CHALLENGE_URL = fn("requestDeviceChallenge");
const ISSUE_SESSION_URL = fn("issueDeviceSession");
const RESPOND_APPROVAL_URL = fn("respondToApprovalRequest");
const RECORD_FISCAL_OPERATION_URL = fn("recordFiscalOperation");
const ISSUE_LEASE_URL = fn("issueOfflineLease");
const REVOKE_LEASE_URL = fn("revokeOfflineLease");

let app: admin.app.App;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID }); });
after(async () => { await app.delete(); });
const db = () => admin.firestore();

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as { result?: Record<string, unknown>; error?: { status?: string; message?: string; details?: Record<string, unknown> } };
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
/** Also self-grants branch access (bootstrapFirstAdminAccount only grants an org-level role) — device registration additionally requires real branch access, which nothing else grants automatically. `manageStaffBranchAccess` itself only becomes checkable once the FIRST sync+refresh has already put the org-level role into the token — a second sync+refresh then picks up the branch grant. */
async function bootstrapRealAdmin(organizationId: string, branchId: string): Promise<{ uid: string; idToken: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  const bootstrap = await callCallable(BOOTSTRAP_URL, { organizationId }, idToken);
  assert.strictEqual(bootstrap.httpStatus, 200, JSON.stringify(bootstrap.body));
  await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  const orgLevelIdToken = await refreshIdToken(refreshToken);

  const grantBranch = await callCallable(GRANT_BRANCH_URL, { organizationId, targetUid: uid, branchId }, orgLevelIdToken);
  assert.strictEqual(grantBranch.httpStatus, 200, JSON.stringify(grantBranch.body));
  await callCallable(SYNC_CLAIMS_URL, {}, orgLevelIdToken);
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
function generateDeviceKeyPair() {
  const { publicKey, privateKey } = generateKeyPairSync("ed25519");
  return { publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString(), sign: (nonce: string) => cryptoSign(null, Buffer.from(nonce, "utf8"), privateKey).toString("base64") };
}
async function activeDeviceSession(organizationId: string, branchId: string, staff: { idToken: string; uid: string }, approver: { idToken: string }) {
  const device = generateDeviceKeyPair();
  const reg = await callCallable(REQUEST_DEVICE_REGISTRATION_URL, { organizationId, branchId, platform: "android", publicKeyPem: device.publicKeyPem, signatureAlgorithm: "ed25519", capabilities: ["POS"] }, staff.idToken);
  assert.strictEqual(reg.httpStatus, 200, JSON.stringify(reg.body));
  const deviceId = reg.body.result?.deviceId as string;
  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: reg.body.result?.approvalRequestId, decision: "approved" }, approver.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));
  const challenge = await callCallable(REQUEST_CHALLENGE_URL, { organizationId, branchId, deviceId, purpose: "issue" }, staff.idToken);
  const signature = device.sign(challenge.body.result?.nonce as string);
  const session = await callCallable(ISSUE_SESSION_URL, { organizationId, branchId, deviceId, challengeId: challenge.body.result?.challengeId, signature }, staff.idToken);
  assert.strictEqual(session.httpStatus, 200, JSON.stringify(session.body));
  return { deviceId, deviceSessionId: session.body.result?.sessionId as string };
}

interface Fixture {
  organizationId: string; restaurantId: string; branchId: string;
  admin1: { idToken: string; uid: string }; manager: { idToken: string; uid: string };
  deviceId: string; deviceSessionId: string;
}
async function setupFixture(): Promise<Fixture> {
  const { organizationId, restaurantId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId, branchId);
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");
  // admin1 registers the device; a SEPARATE actor (manager) approves — a
  // requester can never respond to their own approval request.
  const { deviceId, deviceSessionId } = await activeDeviceSession(organizationId, branchId, admin1, manager);
  return { organizationId, restaurantId, branchId, admin1, manager, deviceId, deviceSessionId };
}
function ctx(f: Fixture) { return { organizationId: f.organizationId, branchId: f.branchId, deviceId: f.deviceId, deviceSessionId: f.deviceSessionId }; }

// -----------------------------------------------------------------------
// recordFiscalOperation
// -----------------------------------------------------------------------

test("recordFiscalOperation: a sale succeeds against the deterministic test adapter and the journal entry reflects it", async () => {
  const f = await setupFixture();
  const res = await callCallable(RECORD_FISCAL_OPERATION_URL, {
    ...ctx(f), operationType: "sale", amountMinorUnits: 5000, currencyCode: "TRY", idempotencyKey: nextId("fisc"),
  }, f.admin1.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  assert.strictEqual(res.body.result?.status, "succeeded");

  const entryDoc = await db().collection("fiscalOperationJournal").doc(res.body.result?.entryId as string).get();
  assert.strictEqual(entryDoc.data()!.status, "succeeded");
  assert.ok(entryDoc.data()!.fiscalDocumentReference);
  assert.strictEqual(entryDoc.data()!.providerId, "testOnlyDeterministic");
});

test("recordFiscalOperation: a retry with the SAME idempotencyKey returns the original journal entry, never a duplicate", async () => {
  const f = await setupFixture();
  const idempotencyKey = nextId("fisc");
  const first = await callCallable(RECORD_FISCAL_OPERATION_URL, { ...ctx(f), operationType: "sale", amountMinorUnits: 5000, currencyCode: "TRY", idempotencyKey }, f.admin1.idToken);
  const second = await callCallable(RECORD_FISCAL_OPERATION_URL, { ...ctx(f), operationType: "sale", amountMinorUnits: 5000, currencyCode: "TRY", idempotencyKey }, f.admin1.idToken);
  assert.strictEqual(second.body.result?.entryId, first.body.result?.entryId);

  const entriesSnap = await db().collection("fiscalOperationJournal").where("idempotencyKey", "==", idempotencyKey).get();
  assert.strictEqual(entriesSnap.size, 1);
});

test("recordFiscalOperation: FORCE_TIMEOUT resolves to timedOut, never silently retried or treated as success", async () => {
  const f = await setupFixture();
  const res = await callCallable(RECORD_FISCAL_OPERATION_URL, {
    ...ctx(f), operationType: "sale", amountMinorUnits: 2000, currencyCode: "TRY", idempotencyKey: `FORCE_TIMEOUT-${nextId("fisc")}`,
  }, f.admin1.idToken);
  assert.strictEqual(res.body.result?.status, "timedOut");
});

test("recordFiscalOperation: FORCE_DECLINE resolves to declined", async () => {
  const f = await setupFixture();
  const res = await callCallable(RECORD_FISCAL_OPERATION_URL, {
    ...ctx(f), operationType: "refund", amountMinorUnits: 1000, currencyCode: "TRY", idempotencyKey: `FORCE_DECLINE-${nextId("fisc")}`,
  }, f.admin1.idToken);
  assert.strictEqual(res.body.result?.status, "declined");
});

// -----------------------------------------------------------------------
// Offline leases
// -----------------------------------------------------------------------

test("issueOfflineLease: a real lease is issued, cash-only, hard ceilings clamp an over-requested count/value/validity", async () => {
  const f = await setupFixture();
  const res = await callCallable(ISSUE_LEASE_URL, {
    ...ctx(f), validityMinutes: 999999, maxTransactionCount: 999999, maxTransactionValueMinorUnits: 999999999,
  }, f.admin1.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  assert.deepStrictEqual(res.body.result?.allowedTenderTypes, ["cash"]);
  assert.strictEqual(res.body.result?.maxTransactionCount, 50, "clamped to the server hard ceiling");
  assert.strictEqual(res.body.result?.maxTransactionValueMinorUnits, 500_000, "clamped to the server hard ceiling");

  const leaseDoc = await db().collection("offlineLeases").doc(res.body.result?.leaseId as string).get();
  assert.strictEqual(leaseDoc.data()!.lastSeenDeviceSequence, 0);
  assert.strictEqual(leaseDoc.data()!.transactionsUsed, 0);
  assert.strictEqual(leaseDoc.data()!.revoked, false);
});

test("revokeOfflineLease: a manager can revoke, idempotently, and the revocation is permanent", async () => {
  const f = await setupFixture();
  const issue = await callCallable(ISSUE_LEASE_URL, { ...ctx(f) }, f.admin1.idToken);
  const leaseId = issue.body.result?.leaseId as string;

  const revoke = await callCallable(REVOKE_LEASE_URL, { organizationId: f.organizationId, branchId: f.branchId, leaseId, reason: "Cihaz kayboldu." }, f.admin1.idToken);
  assert.strictEqual(revoke.httpStatus, 200, JSON.stringify(revoke.body));
  assert.strictEqual(revoke.body.result?.idempotent, false);

  const again = await callCallable(REVOKE_LEASE_URL, { organizationId: f.organizationId, branchId: f.branchId, leaseId, reason: "Tekrar." }, f.admin1.idToken);
  assert.strictEqual(again.body.result?.idempotent, true);

  const leaseDoc = await db().collection("offlineLeases").doc(leaseId).get();
  assert.strictEqual(leaseDoc.data()!.revoked, true);
  assert.strictEqual(leaseDoc.data()!.revokedReason, "Cihaz kayboldu.");
});
