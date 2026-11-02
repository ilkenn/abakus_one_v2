import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * AP-2/staging debugging, 2026-10-27 — the `kitchenWorkItems`-collection
 * sibling of `kitchenTicketQueryRules.test.ts` (see that file's own doc
 * comment for the full root-cause explanation; identical class of bug,
 * different collection). Proves `FirestoreKitchenWorkItemRepository
 * .findByBranch`'s real query shape (`kitchenWorkItems.where('branchId',
 * '==',...).where('organizationId','==',...)`) is what actually satisfies
 * `kitchenWorkItems`' staff-read rule against the real Firestore Emulator,
 * and that the OLD shape (`branchId` only, the one this fix replaced) is
 * rejected outright — confirmed first against the real `abakus-one-staging`
 * project via a raw REST replay before being captured here permanently.
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

async function staffTokenWithBranchAccess(organizationId: string, branchId: string): Promise<string> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles: ["staff"], branchAccess: [branchId], restaurantAccess: [],
    status: "active", createdAt: new Date(), updatedAt: new Date(),
  });
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  return refreshIdToken(refreshToken);
}

async function runWorkItemsQuery(idToken: string, filters: Record<string, unknown>[]) {
  const response = await fetch(
    `${FIRESTORE_HOST}/v1/projects/${EMULATOR_PROJECT_ID}/databases/(default)/documents:runQuery`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json", Authorization: `Bearer ${idToken}` },
      body: JSON.stringify({
        structuredQuery: {
          from: [{ collectionId: "kitchenWorkItems" }],
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

test(
  "the real findByBranch query shape (branchId + organizationId) succeeds for a staff member with real branch access",
  async () => {
    const organizationId = nextId("org");
    const branchId = nextId("branch");
    await admin.firestore().collection("kitchenWorkItems").add({ organizationId, branchId, status: "queued" });
    const idToken = await staffTokenWithBranchAccess(organizationId, branchId);

    const status = await runWorkItemsQuery(idToken, [
      equalsFilter("branchId", branchId),
      equalsFilter("organizationId", organizationId),
    ]);

    assert.strictEqual(status, 200);
  },
);

test(
  "the OLD, regressed query shape (branchId only, no organizationId) is rejected outright, even for the same correctly-permissioned staff member",
  async () => {
    const organizationId = nextId("org");
    const branchId = nextId("branch");
    await admin.firestore().collection("kitchenWorkItems").add({ organizationId, branchId, status: "queued" });
    const idToken = await staffTokenWithBranchAccess(organizationId, branchId);

    const status = await runWorkItemsQuery(idToken, [equalsFilter("branchId", branchId)]);

    assert.strictEqual(
      status,
      403,
      "Firestore must reject this query shape outright — this is the exact regression " +
        "FirestoreKitchenWorkItemRepository.findByBranch's missing organizationId filter caused.",
    );
  },
);

test(
  "the real query shape still correctly denies a staff member with no access to the queried branch",
  async () => {
    const organizationId = nextId("org");
    const branchId = nextId("branch");
    const otherBranchId = nextId("branch");
    await admin.firestore().collection("kitchenWorkItems").add({ organizationId, branchId, status: "queued" });
    const idToken = await staffTokenWithBranchAccess(organizationId, otherBranchId);

    const status = await runWorkItemsQuery(idToken, [
      equalsFilter("branchId", branchId),
      equalsFilter("organizationId", organizationId),
    ]);

    assert.strictEqual(status, 403);
  },
);
