import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { getFirestore } from "firebase-admin/firestore";

/**
 * Emulator-backed tests for `getPreciseFraudEvidence` — FRAUD-F.0
 * (docs/decisions.md, docs/fraud_evidence_architecture.md), the shared
 * fraud-evidence security foundation. Mirrors `provisioning.test.ts`'s
 * exact pattern (raw HTTP against the callable-functions wire protocol,
 * anonymous-sign-up + `setCustomUserClaims` + refresh-token dance for
 * claims-dependent auth contexts) and `registerDeviceToken.test.ts`'s
 * Admin-SDK-seeding style for data this callable never itself creates
 * (FRAUD-F.0 defines no evidence-writing production path — see
 * `functions/src/fraud/fraudEvidenceRepository.ts`'s own doc comment).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const GET_PRECISE_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/getPreciseFraudEvidence`;

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
  const response = await fetch(
    `${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
    },
  );
  const body = (await response.json()) as { id_token: string };
  assert.strictEqual(response.status, 200, "Auth emulator token refresh must succeed");
  return body.id_token;
}

async function mintPlatformOwnerIdToken(): Promise<{ idToken: string; uid: string }> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, { platformRole: "platformOwner" });
  return { idToken: await refreshIdToken(refreshToken), uid };
}

async function mintPlatformAdministratorIdToken(): Promise<string> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, { platformRole: "platformAdministrator" });
  return refreshIdToken(refreshToken);
}

async function mintTenantStaffIdToken(role: string): Promise<string> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, {
    organizationAccess: ["org-1"],
    roles: { "org-1": [role] },
  });
  return refreshIdToken(refreshToken);
}

async function mintPlainIdToken(): Promise<string> {
  const { idToken } = await signUpAnonymously();
  return idToken;
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let seq = 0;
const nextEvidenceId = () => `fraud-evidence-${TEST_RUN_ID}-${++seq}`;

/** Seeds a minimal, valid pre-order FraudEvidence document directly via the
 *  Admin SDK — the only way one can exist in FRAUD-F.0, since no
 *  production capture path is implemented yet. */
async function seedFraudEvidence(overrides: Record<string, unknown> = {}) {
  const id = nextEvidenceId();
  await getFirestore()
    .collection("fraudEvidence")
    .doc(id)
    .set({
      id,
      kind: "addressSave",
      subjectUid: "some-customer",
      organizationId: null,
      branchId: null,
      orderId: null,
      clientLocation: {
        latitude: 41.0,
        longitude: 29.0,
        accuracyMeters: 15,
        clientCapturedAt: new Date().toISOString(),
        mockLocationStatus: "notDetected",
      },
      serverReceivedAt: new Date().toISOString(),
      createdAt: new Date().toISOString(),
      interpretation: {},
      ...overrides,
    });
  return id;
}

async function accessLogEntriesFor(evidenceId: string) {
  const snapshot = await getFirestore()
    .collection("fraudEvidenceAccessLog")
    .where("evidenceId", "==", evidenceId)
    .get();
  return snapshot.docs.map((d) => d.data());
}

test("getPreciseFraudEvidence: an unauthenticated caller is rejected", async () => {
  const evidenceId = await seedFraudEvidence();
  const { httpStatus, body } = await callCallable(GET_PRECISE_URL, { evidenceId });

  assert.notStrictEqual(httpStatus, 200);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("getPreciseFraudEvidence: an ordinary customer is denied", async () => {
  const evidenceId = await seedFraudEvidence();
  const idToken = await mintPlainIdToken();

  const { httpStatus, body } = await callCallable(GET_PRECISE_URL, { evidenceId }, idToken);

  assert.notStrictEqual(httpStatus, 200);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("getPreciseFraudEvidence: tenant staff is denied", async () => {
  const evidenceId = await seedFraudEvidence();
  const idToken = await mintTenantStaffIdToken("staff");

  const { httpStatus, body } = await callCallable(GET_PRECISE_URL, { evidenceId }, idToken);

  assert.notStrictEqual(httpStatus, 200);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("getPreciseFraudEvidence: tenant admin is denied", async () => {
  const evidenceId = await seedFraudEvidence();
  const idToken = await mintTenantStaffIdToken("admin");

  const { httpStatus, body } = await callCallable(GET_PRECISE_URL, { evidenceId }, idToken);

  assert.notStrictEqual(httpStatus, 200);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("getPreciseFraudEvidence: platformAdministrator is denied — this capability is platformOwner-only", async () => {
  const evidenceId = await seedFraudEvidence();
  const idToken = await mintPlatformAdministratorIdToken();

  const { httpStatus, body } = await callCallable(GET_PRECISE_URL, { evidenceId }, idToken);

  assert.notStrictEqual(httpStatus, 200);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("getPreciseFraudEvidence: platformOwner (the capable caller) succeeds and receives the evidence", async () => {
  const evidenceId = await seedFraudEvidence({ subjectUid: "customer-xyz" });
  const { idToken } = await mintPlatformOwnerIdToken();

  const { httpStatus, body } = await callCallable(GET_PRECISE_URL, { evidenceId }, idToken);

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual((body.result?.evidence as Record<string, unknown>)?.subjectUid, "customer-xyz");
});

test("getPreciseFraudEvidence: a missing evidence id is handled safely (not-found, not a crash)", async () => {
  const { idToken } = await mintPlatformOwnerIdToken();

  const { httpStatus, body } = await callCallable(
    GET_PRECISE_URL,
    { evidenceId: `nonexistent-${TEST_RUN_ID}` },
    idToken,
  );

  assert.notStrictEqual(httpStatus, 200);
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});

test("getPreciseFraudEvidence: a successful access is written to fraudEvidenceAccessLog with the real actor and evidence id", async () => {
  const evidenceId = await seedFraudEvidence();
  const { idToken, uid } = await mintPlatformOwnerIdToken();

  await callCallable(GET_PRECISE_URL, { evidenceId }, idToken);

  const entries = await accessLogEntriesFor(evidenceId);
  assert.strictEqual(entries.length, 1);
  assert.strictEqual(entries[0].actorUid, uid);
  assert.strictEqual(entries[0].capability, "fraudEvidence.readPrecise");
  assert.strictEqual(entries[0].action, "read");
});

test("getPreciseFraudEvidence: a denied attempt writes NO access-log entry at all", async () => {
  const evidenceId = await seedFraudEvidence();
  const idToken = await mintPlainIdToken();

  await callCallable(GET_PRECISE_URL, { evidenceId }, idToken);

  const entries = await accessLogEntriesFor(evidenceId);
  assert.strictEqual(entries.length, 0, "denied access must never produce an audit-log entry");
});

test("getPreciseFraudEvidence: the access log is append-only — two reads of the same evidence produce two distinct immutable entries, never one updated entry", async () => {
  const evidenceId = await seedFraudEvidence();
  const { idToken } = await mintPlatformOwnerIdToken();

  await callCallable(GET_PRECISE_URL, { evidenceId }, idToken);
  await callCallable(GET_PRECISE_URL, { evidenceId }, idToken);

  const entries = await accessLogEntriesFor(evidenceId);
  assert.strictEqual(entries.length, 2, "each access must append a new entry, never overwrite the prior one");
  assert.notStrictEqual(entries[0].accessedAt, undefined);
  assert.notStrictEqual(entries[1].accessedAt, undefined);
});

test("getPreciseFraudEvidence: the capability cannot be forged via request data — an ordinary customer claiming platformRole in the payload is still denied", async () => {
  const evidenceId = await seedFraudEvidence();
  const idToken = await mintPlainIdToken();

  const { httpStatus, body } = await callCallable(
    GET_PRECISE_URL,
    { evidenceId, platformRole: "platformOwner", capability: "fraudEvidence.readPrecise" },
    idToken,
  );

  assert.notStrictEqual(httpStatus, 200);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("getPreciseFraudEvidence: no cross-resource shortcut — requesting evidence A never returns evidence B's data", async () => {
  const evidenceIdA = await seedFraudEvidence({ subjectUid: "customer-a" });
  await seedFraudEvidence({ subjectUid: "customer-b" });
  const { idToken } = await mintPlatformOwnerIdToken();

  const { body } = await callCallable(GET_PRECISE_URL, { evidenceId: evidenceIdA }, idToken);

  assert.strictEqual((body.result?.evidence as Record<string, unknown>)?.subjectUid, "customer-a");
});

test("getPreciseFraudEvidence: App Check state is never accepted from request data — a forged field has zero effect on an otherwise-authorized call", async () => {
  const evidenceId = await seedFraudEvidence({ subjectUid: "customer-appcheck" });
  const { idToken } = await mintPlatformOwnerIdToken();

  const { httpStatus, body } = await callCallable(
    GET_PRECISE_URL,
    { evidenceId, appCheckState: "VERIFIED", attestationState: "PASSED", trustedDevice: true },
    idToken,
  );

  // The emulator never sends a real App Check token in this raw-HTTP test
  // harness, so `enforceAppCheck` (currently `false` under the emulator
  // regardless — see appCheckConfig.ts) never blocks this call either way;
  // what this test actually proves is that the forged fields have no
  // effect at all — the call succeeds or fails purely on the real
  // platformRole claim, and the returned evidence is unaffected.
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual((body.result?.evidence as Record<string, unknown>)?.subjectUid, "customer-appcheck");
});

test("getPreciseFraudEvidence: a missing evidenceId argument is rejected", async () => {
  const { idToken } = await mintPlatformOwnerIdToken();

  const { httpStatus, body } = await callCallable(GET_PRECISE_URL, {}, idToken);

  assert.notStrictEqual(httpStatus, 200);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});
