import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * AP-2/staging debugging, 2026-10-27 — the `customerPhotos`-collection
 * sibling of `kitchenTicketQueryRules.test.ts`/`adminOrdersQueryRules.test.ts`.
 * Proves `FirestoreCustomerPhotoRepository.findPendingReview`'s real query
 * shape (`customerPhotos.where('organizationId','==',...).where('status',
 * 'in',['pendingReview','underReview'])`, the Fotoğraf Denetimi screen's
 * read path) satisfies `customerPhotos`' staff-read rule
 * (`isOwner(resource.data.customerId) || isOrgMember(resource.data
 * .organizationId)`) against the real Firestore Emulator, and that a
 * `status`-only shape (no `organizationId`) is rejected outright — written
 * correctly from the start here, but pinned down anyway, matching this
 * session's own established discipline.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const AUTH_HOST = "http://127.0.0.1:9099";
const FIRESTORE_HOST = "http://127.0.0.1:8080";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const SYNC_CLAIMS_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/syncOwnStaffClaims`;

let app: admin.app.App;

before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});

after(async () => {
  await app.delete();
});

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function callCallable(url: string, data: Record<string, unknown>, idToken: string) {
  const response = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json", Authorization: `Bearer ${idToken}` },
    body: JSON.stringify({ data }),
  });
  return { httpStatus: response.status, body: await response.json() };
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

async function staffTokenForOrg(organizationId: string): Promise<string> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles: ["staff"], branchAccess: [], restaurantAccess: [],
    status: "active", createdAt: new Date(), updatedAt: new Date(),
  });
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  return refreshIdToken(refreshToken);
}

async function runPhotosQuery(idToken: string, filters: Record<string, unknown>[]) {
  const response = await fetch(
    `${FIRESTORE_HOST}/v1/projects/${EMULATOR_PROJECT_ID}/databases/(default)/documents:runQuery`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${idToken}` },
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: "customerPhotos" }],
          where: { compositeFilter: { op: "AND", filters } },
        },
      }),
    },
  );
  return response.status;
}

function equalsFilter(field: string, value: string) {
  return { fieldFilter: { field: { fieldPath: field }, op: "EQUAL", value: { stringValue: value } } };
}
function statusInFilter(statuses: string[]) {
  return {
    fieldFilter: {
      field: { fieldPath: "status" },
      op: "IN",
      value: { arrayValue: { values: statuses.map((s) => ({ stringValue: s })) } },
    },
  };
}

test(
  "the real moderation-queue query shape (organizationId + status IN) succeeds for a same-org staff member",
  async () => {
    const organizationId = nextId("org");
    await admin.firestore().collection("customerPhotos").add({
      organizationId, customerId: nextId("customer"), status: "pendingReview",
    });
    const idToken = await staffTokenForOrg(organizationId);

    const status = await runPhotosQuery(idToken, [
      equalsFilter("organizationId", organizationId),
      statusInFilter(["pendingReview", "underReview"]),
    ]);

    assert.strictEqual(status, 200);
  },
);

test(
  "a status-only shape (no organizationId) is rejected outright, even for the same staff member",
  async () => {
    const organizationId = nextId("org");
    await admin.firestore().collection("customerPhotos").add({
      organizationId, customerId: nextId("customer"), status: "pendingReview",
    });
    const idToken = await staffTokenForOrg(organizationId);

    const status = await runPhotosQuery(idToken, [statusInFilter(["pendingReview", "underReview"])]);

    assert.strictEqual(status, 403);
  },
);

test(
  "the real query shape still correctly denies a staff member of a different organization",
  async () => {
    const organizationId = nextId("org");
    const otherOrganizationId = nextId("org");
    await admin.firestore().collection("customerPhotos").add({
      organizationId, customerId: nextId("customer"), status: "pendingReview",
    });
    const idToken = await staffTokenForOrg(otherOrganizationId);

    const status = await runPhotosQuery(idToken, [
      equalsFilter("organizationId", organizationId),
      statusInFilter(["pendingReview", "underReview"]),
    ]);

    assert.strictEqual(status, 403);
  },
);
