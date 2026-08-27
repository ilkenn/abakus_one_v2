import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { generateKeyPairSync, sign as cryptoSign } from "crypto";

/**
 * Emulator-backed tests for AP-2 Stage B's trusted-device online
 * foundation + the remote approval engine's device-activation reference
 * action. Mirrors `staffMembership.test.ts`'s harness. A real Ed25519
 * keypair is generated per test "device" (Node's own `crypto` module —
 * no plugin/hardware dependency), so the challenge/signature protocol is
 * exercised for real, not mocked.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const ASSIGN_ROLE_URL = fn("assignStaffRole");
const GRANT_BRANCH_URL = fn("grantStaffBranchAccess");
const REQUEST_DEVICE_REGISTRATION_URL = fn("requestDeviceRegistration");
const REQUEST_CHALLENGE_URL = fn("requestDeviceChallenge");
const ISSUE_SESSION_URL = fn("issueDeviceSession");
const REVOKE_DEVICE_URL = fn("revokeTrustedDevice");
const SUSPEND_DEVICE_URL = fn("suspendTrustedDevice");
const RETIRE_DEVICE_URL = fn("retireTrustedDevice");
const RESPOND_APPROVAL_URL = fn("respondToApprovalRequest");
const SWEEP_APPROVAL_URL = fn("sweepExpiredApprovalRequests");

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
  // Device registration for POS/KDS capability requires the module to be
  // entitled — seeded directly (Admin SDK) as a test fixture, mirroring
  // seedReservationPolicy's own precedent, not through grantEntitlement
  // (out of this file's own scope).
  await admin.firestore().collection("entitlements").doc(`${organizationId}_organization_${organizationId}_pos`).set({
    organizationId, scopeType: "organization", scopeId: organizationId, module: "pos", status: "active", version: 1,
  });
  await admin.firestore().collection("entitlements").doc(`${organizationId}_organization_${organizationId}_kds`).set({
    organizationId, scopeType: "organization", scopeId: organizationId, module: "kds", status: "active", version: 1,
  });
  return { organizationId, restaurantId, branchId };
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
  await admin.firestore().collection("memberships").doc(`${organizationId}_${uid}`).set({
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
  return {
    publicKeyPem: publicKey.export({ type: "spki", format: "pem" }).toString(),
    sign: (nonce: string) => cryptoSign(null, Buffer.from(nonce, "utf8"), privateKey).toString("base64"),
  };
}

async function registerAndActivateDevice(
  organizationId: string,
  branchId: string,
  registerer: { idToken: string; uid: string },
  approver: { idToken: string },
  platform = "android",
) {
  const device = generateDeviceKeyPair();
  const reg = await callCallable(
    REQUEST_DEVICE_REGISTRATION_URL,
    { organizationId, branchId, platform, publicKeyPem: device.publicKeyPem, signatureAlgorithm: "ed25519", capabilities: ["POS"] },
    registerer.idToken,
  );
  assert.strictEqual(reg.httpStatus, 200, JSON.stringify(reg.body));
  const deviceId = reg.body.result?.deviceId as string;
  const approvalRequestId = reg.body.result?.approvalRequestId as string;

  const respond = await callCallable(RESPOND_APPROVAL_URL, { requestId: approvalRequestId, decision: "approved" }, approver.idToken);
  assert.strictEqual(respond.httpStatus, 200, JSON.stringify(respond.body));

  return { deviceId, device, approvalRequestId, trustTier: reg.body.result?.trustTier as string };
}

test("requestDeviceRegistration: a POS-capability request is rejected server-side when the pos module is not entitled, even though the client's own gate might allow it", async () => {
  const { organizationId, branchId } = await seedTenant();
  await admin.firestore().collection("entitlements").doc(`${organizationId}_organization_${organizationId}_pos`).update({ status: "suspended" });
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const device = generateDeviceKeyPair();

  const reg = await callCallable(
    REQUEST_DEVICE_REGISTRATION_URL,
    { organizationId, branchId, platform: "android", publicKeyPem: device.publicKeyPem, signatureAlgorithm: "ed25519", capabilities: ["POS"] },
    staff.idToken,
  );
  assert.strictEqual(reg.httpStatus, 400, JSON.stringify(reg.body)); // failed-precondition
});

test("full reference-action flow: register -> pending approval -> manager approves -> device active -> challenge -> session issued", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");

  const { deviceId, device } = await registerAndActivateDevice(organizationId, branchId, staff, admin1);

  const regDoc = await admin.firestore().collection("trustedDeviceRegistrations").doc(`${organizationId}_${branchId}_${deviceId}`).get();
  assert.strictEqual(regDoc.data()?.status, "active");

  const challenge = await callCallable(REQUEST_CHALLENGE_URL, { organizationId, branchId, deviceId, purpose: "issue" }, staff.idToken);
  assert.strictEqual(challenge.httpStatus, 200, JSON.stringify(challenge.body));
  const nonce = challenge.body.result?.nonce as string;
  const challengeId = challenge.body.result?.challengeId as string;
  const signature = device.sign(nonce);

  const session = await callCallable(ISSUE_SESSION_URL, { organizationId, branchId, deviceId, challengeId, signature }, staff.idToken);
  assert.strictEqual(session.httpStatus, 200, JSON.stringify(session.body));
  assert.ok(session.body.result?.sessionId);
});

test("device activation: the requester cannot approve their own device registration (self-approval forbidden)", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");

  const device = generateDeviceKeyPair();
  const reg = await callCallable(
    REQUEST_DEVICE_REGISTRATION_URL,
    { organizationId, branchId, platform: "android", publicKeyPem: device.publicKeyPem, signatureAlgorithm: "ed25519", capabilities: ["POS"] },
    manager.idToken,
  );
  assert.strictEqual(reg.httpStatus, 200, JSON.stringify(reg.body));

  const selfApprove = await callCallable(
    RESPOND_APPROVAL_URL,
    { requestId: reg.body.result?.approvalRequestId, decision: "approved" },
    manager.idToken,
  );
  assert.strictEqual(selfApprove.httpStatus, 403, JSON.stringify(selfApprove.body));
});

test("device activation: a conflicting second response is rejected, an idempotent identical response returns the existing result", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");

  const device = generateDeviceKeyPair();
  const reg = await callCallable(
    REQUEST_DEVICE_REGISTRATION_URL,
    { organizationId, branchId, platform: "android", publicKeyPem: device.publicKeyPem, signatureAlgorithm: "ed25519", capabilities: ["POS"] },
    staff.idToken,
  );
  const requestId = reg.body.result?.approvalRequestId as string;

  const approve = await callCallable(RESPOND_APPROVAL_URL, { requestId, decision: "approved" }, manager.idToken);
  assert.strictEqual(approve.httpStatus, 200, JSON.stringify(approve.body));

  // Same responder, same decision — idempotent no-op, not an error.
  const again = await callCallable(RESPOND_APPROVAL_URL, { requestId, decision: "approved" }, manager.idToken);
  assert.strictEqual(again.httpStatus, 200, JSON.stringify(again.body));
  assert.strictEqual(again.body.result?.idempotent, true);

  // A different manager attempting to REJECT an already-approved request — conflicting, rejected.
  const secondManager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");
  const conflicting = await callCallable(RESPOND_APPROVAL_URL, { requestId, decision: "rejected" }, secondManager.idToken);
  assert.strictEqual(conflicting.httpStatus, 400, JSON.stringify(conflicting.body)); // failed-precondition
});

test("device activation: stale target — a device whose version has already changed before approval is rejected", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");

  const device = generateDeviceKeyPair();
  const reg = await callCallable(
    REQUEST_DEVICE_REGISTRATION_URL,
    { organizationId, branchId, platform: "android", publicKeyPem: device.publicKeyPem, signatureAlgorithm: "ed25519", capabilities: ["POS"] },
    staff.idToken,
  );
  const deviceId = reg.body.result?.deviceId as string;
  const requestId = reg.body.result?.approvalRequestId as string;

  // Mutate the target's version directly, simulating a real change that
  // happened between request creation and approval.
  await admin.firestore().collection("trustedDeviceRegistrations").doc(`${organizationId}_${branchId}_${deviceId}`).update({ version: 99 });

  const approve = await callCallable(RESPOND_APPROVAL_URL, { requestId, decision: "approved" }, manager.idToken);
  assert.strictEqual(approve.httpStatus, 400, JSON.stringify(approve.body)); // failed-precondition
});

test("device registration: web platform resolves UNSUPPORTED_OR_UNTRUSTED and can never be issued an operational session", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");

  const { deviceId, device, trustTier } = await registerAndActivateDevice(organizationId, branchId, staff, admin1, "web");
  assert.strictEqual(trustTier, "UNSUPPORTED_OR_UNTRUSTED");

  const challenge = await callCallable(REQUEST_CHALLENGE_URL, { organizationId, branchId, deviceId, purpose: "issue" }, staff.idToken);
  assert.strictEqual(challenge.httpStatus, 200, JSON.stringify(challenge.body));
  const signature = device.sign(challenge.body.result?.nonce as string);
  const session = await callCallable(
    ISSUE_SESSION_URL,
    { organizationId, branchId, deviceId, challengeId: challenge.body.result?.challengeId, signature },
    staff.idToken,
  );
  assert.strictEqual(session.httpStatus, 400, JSON.stringify(session.body)); // failed-precondition
});

test("device session: a forged signature is rejected", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId } = await registerAndActivateDevice(organizationId, branchId, staff, admin1);

  const challenge = await callCallable(REQUEST_CHALLENGE_URL, { organizationId, branchId, deviceId, purpose: "issue" }, staff.idToken);
  const wrongDevice = generateDeviceKeyPair();
  const forgedSignature = wrongDevice.sign(challenge.body.result?.nonce as string);

  const session = await callCallable(
    ISSUE_SESSION_URL,
    { organizationId, branchId, deviceId, challengeId: challenge.body.result?.challengeId, signature: forgedSignature },
    staff.idToken,
  );
  assert.strictEqual(session.httpStatus, 403, JSON.stringify(session.body));
});

test("device session: a challenge is single-use — replaying the same challengeId/signature a second time is rejected", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId, device } = await registerAndActivateDevice(organizationId, branchId, staff, admin1);

  const challenge = await callCallable(REQUEST_CHALLENGE_URL, { organizationId, branchId, deviceId, purpose: "issue" }, staff.idToken);
  const signature = device.sign(challenge.body.result?.nonce as string);
  const payload = { organizationId, branchId, deviceId, challengeId: challenge.body.result?.challengeId, signature };

  const first = await callCallable(ISSUE_SESSION_URL, payload, staff.idToken);
  assert.strictEqual(first.httpStatus, 200, JSON.stringify(first.body));

  const replay = await callCallable(ISSUE_SESSION_URL, payload, staff.idToken);
  assert.strictEqual(replay.httpStatus, 400, JSON.stringify(replay.body)); // failed-precondition: already consumed
});

test("revokeTrustedDevice: immediate revocation, idempotent on a second call, and blocks a subsequent session issuance", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  // Bootstrap admin starts with branchAccess: [] (documented codebase
  // invariant — no role-based bypass, not even admin) — revokeTrustedDevice
  // correctly requires real branch access, so the revoker here must be a
  // manager who was actually granted access to this branch, not the bootstrap
  // admin itself.
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");
  const { deviceId } = await registerAndActivateDevice(organizationId, branchId, staff, admin1);

  const revoke = await callCallable(REVOKE_DEVICE_URL, { organizationId, branchId, deviceId, reason: "lost device" }, manager.idToken);
  assert.strictEqual(revoke.httpStatus, 200, JSON.stringify(revoke.body));
  assert.strictEqual(revoke.body.result?.revoked, true);

  const revokeAgain = await callCallable(REVOKE_DEVICE_URL, { organizationId, branchId, deviceId, reason: "already lost" }, manager.idToken);
  assert.strictEqual(revokeAgain.httpStatus, 200, JSON.stringify(revokeAgain.body));
  assert.strictEqual(revokeAgain.body.result?.alreadyRevoked, true);

  const challenge = await callCallable(REQUEST_CHALLENGE_URL, { organizationId, branchId, deviceId, purpose: "issue" }, staff.idToken);
  assert.strictEqual(challenge.httpStatus, 400, JSON.stringify(challenge.body)); // device not active
});

test("wrong-branch device: a device registered for one branch cannot be operated by a staff member scoped to a different branch", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staffOnBranchA = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const { deviceId } = await registerAndActivateDevice(organizationId, branchId, staffOnBranchA, admin1);

  const otherBranchId = nextId("branch");
  await admin.firestore().collection("branches").doc(otherBranchId).set({
    restaurantId: nextId("restaurant"), organizationId, name: "Other Branch", status: "active", emergencyStopped: false,
  });
  const staffOnBranchB = await newStaffMember(organizationId, otherBranchId, admin1.idToken, "staff");

  const challenge = await callCallable(
    REQUEST_CHALLENGE_URL,
    { organizationId, branchId: otherBranchId, deviceId, purpose: "issue" },
    staffOnBranchB.idToken,
  );
  assert.strictEqual(challenge.httpStatus, 404, JSON.stringify(challenge.body)); // no such registration under that branch
});

test("suspendTrustedDevice: manager suspends an active device, idempotent on a second call, blocks a subsequent challenge, and requires manageDevices (staff cannot)", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");
  const { deviceId } = await registerAndActivateDevice(organizationId, branchId, staff, admin1);

  const staffAttempt = await callCallable(
    SUSPEND_DEVICE_URL,
    { organizationId, branchId, deviceId, reason: "staff attempting a manager-only action" },
    staff.idToken,
  );
  assert.strictEqual(staffAttempt.httpStatus, 403, JSON.stringify(staffAttempt.body));

  const suspend = await callCallable(SUSPEND_DEVICE_URL, { organizationId, branchId, deviceId, reason: "routine check" }, manager.idToken);
  assert.strictEqual(suspend.httpStatus, 200, JSON.stringify(suspend.body));
  assert.strictEqual(suspend.body.result?.status, "suspended");
  assert.strictEqual(suspend.body.result?.changed, true);

  const suspendAgain = await callCallable(SUSPEND_DEVICE_URL, { organizationId, branchId, deviceId, reason: "again" }, manager.idToken);
  assert.strictEqual(suspendAgain.httpStatus, 200, JSON.stringify(suspendAgain.body));
  assert.strictEqual(suspendAgain.body.result?.changed, false);

  const challenge = await callCallable(REQUEST_CHALLENGE_URL, { organizationId, branchId, deviceId, purpose: "issue" }, staff.idToken);
  assert.strictEqual(challenge.httpStatus, 400, JSON.stringify(challenge.body)); // device not active
});

test("retireTrustedDevice: manager retires a device from any non-retired status, idempotent on a second call, revokes its active sessions", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");
  const { deviceId, device } = await registerAndActivateDevice(organizationId, branchId, staff, admin1);

  const challenge = await callCallable(REQUEST_CHALLENGE_URL, { organizationId, branchId, deviceId, purpose: "issue" }, staff.idToken);
  const session = await callCallable(
    ISSUE_SESSION_URL,
    { organizationId, branchId, deviceId, challengeId: challenge.body.result?.challengeId, signature: device.sign(challenge.body.result?.nonce as string) },
    staff.idToken,
  );
  const sessionId = session.body.result?.sessionId as string;

  const retire = await callCallable(RETIRE_DEVICE_URL, { organizationId, branchId, deviceId, reason: "hardware end of life" }, manager.idToken);
  assert.strictEqual(retire.httpStatus, 200, JSON.stringify(retire.body));
  assert.strictEqual(retire.body.result?.status, "retired");
  assert.strictEqual(retire.body.result?.changed, true);

  const sessionDoc = await admin.firestore().collection("deviceSessions").doc(sessionId).get();
  assert.strictEqual(sessionDoc.data()?.status, "revoked");

  const retireAgain = await callCallable(RETIRE_DEVICE_URL, { organizationId, branchId, deviceId, reason: "already retired" }, manager.idToken);
  assert.strictEqual(retireAgain.httpStatus, 200, JSON.stringify(retireAgain.body));
  assert.strictEqual(retireAgain.body.result?.changed, false);
});

test("respondToApprovalRequest: an optional reasonMessage is sanitized and persisted on the approvalEvents entry; absent/blank never stored as an empty string", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");
  const manager = await newStaffMember(organizationId, branchId, admin1.idToken, "manager");

  const device = generateDeviceKeyPair();
  const reg = await callCallable(
    REQUEST_DEVICE_REGISTRATION_URL,
    { organizationId, branchId, platform: "android", publicKeyPem: device.publicKeyPem, signatureAlgorithm: "ed25519", capabilities: ["POS"] },
    staff.idToken,
  );
  const requestId = reg.body.result?.approvalRequestId as string;

  const approve = await callCallable(RESPOND_APPROVAL_URL, { requestId, decision: "approved", reasonMessage: "  verified with branch manager on call  " }, manager.idToken);
  assert.strictEqual(approve.httpStatus, 200, JSON.stringify(approve.body));

  const events = await admin.firestore().collection("approvalEvents").where("requestId", "==", requestId).get();
  assert.strictEqual(events.size, 1);
  assert.strictEqual(events.docs[0].data().reasonMessage, "verified with branch manager on call");

  // A second, independent request with a blank reasonMessage stores null, never "".
  const device2 = generateDeviceKeyPair();
  const reg2 = await callCallable(
    REQUEST_DEVICE_REGISTRATION_URL,
    { organizationId, branchId, platform: "android", publicKeyPem: device2.publicKeyPem, signatureAlgorithm: "ed25519", capabilities: ["POS"] },
    staff.idToken,
  );
  const requestId2 = reg2.body.result?.approvalRequestId as string;
  const approve2 = await callCallable(RESPOND_APPROVAL_URL, { requestId: requestId2, decision: "approved", reasonMessage: "   " }, manager.idToken);
  assert.strictEqual(approve2.httpStatus, 200, JSON.stringify(approve2.body));
  const events2 = await admin.firestore().collection("approvalEvents").where("requestId", "==", requestId2).get();
  assert.strictEqual(events2.docs[0].data().reasonMessage, null);
});

test("sweepExpiredApprovalRequests: a pending request past its expiry is escalated, then expired on a later sweep", async () => {
  const { organizationId, branchId } = await seedTenant();
  const admin1 = await bootstrapRealAdmin(organizationId);
  const staff = await newStaffMember(organizationId, branchId, admin1.idToken, "staff");

  const device = generateDeviceKeyPair();
  const reg = await callCallable(
    REQUEST_DEVICE_REGISTRATION_URL,
    { organizationId, branchId, platform: "android", publicKeyPem: device.publicKeyPem, signatureAlgorithm: "ed25519", capabilities: ["POS"] },
    staff.idToken,
  );
  const requestId = reg.body.result?.approvalRequestId as string;

  await admin.firestore().collection("remoteApprovalRequests").doc(requestId).update({
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000),
  });

  const sweep1 = await callCallable(SWEEP_APPROVAL_URL, {});
  assert.strictEqual(sweep1.httpStatus, 200, JSON.stringify(sweep1.body));
  assert.ok((sweep1.body.result?.escalated as number) >= 1);

  const afterFirstSweep = await admin.firestore().collection("remoteApprovalRequests").doc(requestId).get();
  assert.strictEqual(afterFirstSweep.data()?.status, "escalated");

  await admin.firestore().collection("remoteApprovalRequests").doc(requestId).update({
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000),
  });
  const sweep2 = await callCallable(SWEEP_APPROVAL_URL, {});
  assert.ok((sweep2.body.result?.expired as number) >= 1);
  const afterSecondSweep = await admin.firestore().collection("remoteApprovalRequests").doc(requestId).get();
  assert.strictEqual(afterSecondSweep.data()?.status, "expired");
});
