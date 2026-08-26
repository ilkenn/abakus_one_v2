import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/** Emulator-backed tests for AP-2's `listStaffMembersForOrganization` read model. */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const ASSIGN_ROLE_URL = fn("assignStaffRole");
const LIST_STAFF_URL = fn("listStaffMembersForOrganization");

let app: admin.app.App;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID }); });
after(async () => { await app.delete(); });

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as { result?: Record<string, unknown>; error?: { status?: string; message?: string } };
  return { httpStatus: response.status, body };
}

async function signUpAnonymously(): Promise<{ idToken: string; refreshToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken: string; refreshToken: string; localId: string };
  assert.strictEqual(response.status, 200);
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}

async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  const body = (await response.json()) as { id_token: string };
  assert.strictEqual(response.status, 200);
  return body.id_token;
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function bootstrapRealAdmin(organizationId: string) {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  const bootstrap = await callCallable(BOOTSTRAP_URL, { organizationId }, idToken);
  assert.strictEqual(bootstrap.httpStatus, 200, JSON.stringify(bootstrap.body));
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  return { uid, idToken: await refreshIdToken(refreshToken) };
}

test("listStaffMembersForOrganization: unauthenticated caller rejected; a caller with no relevant permission is rejected", async () => {
  const organizationId = nextId("org");
  const unauth = await callCallable(LIST_STAFF_URL, { organizationId });
  assert.strictEqual(unauth.httpStatus, 401, JSON.stringify(unauth.body));

  const { idToken: bareToken } = await signUpAnonymously();
  const noPermission = await callCallable(LIST_STAFF_URL, { organizationId }, bareToken);
  assert.strictEqual(noPermission.httpStatus, 403, JSON.stringify(noPermission.body));
});

test("listStaffMembersForOrganization: an admin sees every real membership in their organization, never another organization's", async () => {
  const organizationId = nextId("org");
  const otherOrganizationId = nextId("org");
  const admin1 = await bootstrapRealAdmin(organizationId);
  await bootstrapRealAdmin(otherOrganizationId);

  const { uid: staffUid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${organizationId}_${staffUid}`).set({
    organizationId, uid: staffUid, roles: ["staff"], branchAccess: [], restaurantAccess: [], status: "active", version: 1,
  });
  await callCallable(ASSIGN_ROLE_URL, { organizationId, targetUid: staffUid, role: "staff" }, admin1.idToken);

  const res = await callCallable(LIST_STAFF_URL, { organizationId }, admin1.idToken);
  assert.strictEqual(res.httpStatus, 200, JSON.stringify(res.body));
  const members = res.body.result?.members as Array<{ uid: string }>;
  const uids = members.map((m) => m.uid);
  assert.ok(uids.includes(admin1.uid));
  assert.ok(uids.includes(staffUid));
  assert.strictEqual(members.length, 2);
});
