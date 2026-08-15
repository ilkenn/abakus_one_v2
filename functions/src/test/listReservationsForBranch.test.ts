import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `listReservationsForBranch` — Faz R.3A §4.
 * Fixtures write `reservations` documents directly via the Admin SDK
 * (this collection has no client write path at all — `submitReservation`
 * is the only legitimate writer — so a direct Admin SDK write is the only
 * way to seed varied fixture data without driving the full submit/confirm
 * flow for every scenario) rather than exercising `submitReservation` for
 * every fixture, mirroring how other list-shaped tests in this codebase
 * seed bucket/occupancy fixtures directly.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const LIST_URL = fn("listReservationsForBranch");
const AUTH_HOST = "http://127.0.0.1:9099";

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
    result?: { reservations: Record<string, unknown>[]; nextCursor: string | null };
    error?: { status?: string; message?: string };
  };
  return { httpStatus: response.status, body };
}

async function signUpAnonymously() {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { refreshToken: string; localId: string };
  return body;
}
async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  const body = (await response.json()) as { id_token: string };
  return body.id_token;
}
async function mintStaffIdToken(organizationId: string, roles: string[]): Promise<string> {
  const { refreshToken, localId } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(localId, { organizationAccess: [organizationId], roles: { [organizationId]: roles } });
  return refreshIdToken(refreshToken);
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function seedReservation(overrides: Record<string, unknown>) {
  const id = nextId("reservation");
  await admin.firestore().collection("reservations").doc(id).set({
    status: "pendingRestaurantApproval",
    partySize: 2,
    requestedAreaId: "area-garden",
    contactFirstName: "Ada",
    contactLastName: "Yılmaz",
    confirmedTime: null,
    confirmedAreaId: null,
    assignedTableId: null,
    preorderOrderId: null,
    activeProposalCustomerResponseDeadlineAt: null,
    ...overrides,
  });
  return id;
}

test("listReservationsForBranch: returns only reservations for the given branch within the date range, sorted by requestedTime", async () => {
  const organizationId = nextId("org");
  const branchId = nextId("branch");
  const otherBranchId = nextId("branch");
  const base = new Date("2026-08-20T00:00:00.000Z").getTime();

  const idA = await seedReservation({ organizationId, branchId, requestedTime: new Date(base + 2 * 3_600_000) });
  const idB = await seedReservation({ organizationId, branchId, requestedTime: new Date(base + 1 * 3_600_000) });
  await seedReservation({ organizationId, branchId: otherBranchId, requestedTime: new Date(base + 1 * 3_600_000) });
  await seedReservation({ organizationId, branchId, requestedTime: new Date(base - 48 * 3_600_000) }); // out of range

  const idToken = await mintStaffIdToken(organizationId, ["manager"]);
  const result = await callCallable(
    LIST_URL,
    {
      organizationId,
      branchId,
      dateFrom: new Date(base - 3_600_000).toISOString(),
      dateTo: new Date(base + 6 * 3_600_000).toISOString(),
    },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const ids = result.body.result!.reservations.map((r) => r.id);
  assert.deepStrictEqual(ids, [idB, idA]);
});

test("listReservationsForBranch: status filter narrows results in-memory", async () => {
  const organizationId = nextId("org");
  const branchId = nextId("branch");
  const base = new Date("2026-08-21T00:00:00.000Z").getTime();
  const idConfirmed = await seedReservation({ organizationId, branchId, status: "confirmed", requestedTime: new Date(base) });
  await seedReservation({ organizationId, branchId, status: "rejected", requestedTime: new Date(base + 3_600_000) });

  const idToken = await mintStaffIdToken(organizationId, ["manager"]);
  const result = await callCallable(
    LIST_URL,
    {
      organizationId,
      branchId,
      dateFrom: new Date(base - 3_600_000).toISOString(),
      dateTo: new Date(base + 6 * 3_600_000).toISOString(),
      statuses: ["confirmed"],
    },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  assert.deepStrictEqual(result.body.result!.reservations.map((r) => r.id), [idConfirmed]);
});

test("listReservationsForBranch: areaId filter narrows results in-memory", async () => {
  const organizationId = nextId("org");
  const branchId = nextId("branch");
  const base = new Date("2026-08-22T00:00:00.000Z").getTime();
  const idGarden = await seedReservation({ organizationId, branchId, requestedAreaId: "area-garden", requestedTime: new Date(base) });
  await seedReservation({ organizationId, branchId, requestedAreaId: "area-indoor", requestedTime: new Date(base + 3_600_000) });

  const idToken = await mintStaffIdToken(organizationId, ["manager"]);
  const result = await callCallable(
    LIST_URL,
    {
      organizationId,
      branchId,
      dateFrom: new Date(base - 3_600_000).toISOString(),
      dateTo: new Date(base + 6 * 3_600_000).toISOString(),
      areaId: "area-garden",
    },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  assert.deepStrictEqual(result.body.result!.reservations.map((r) => r.id), [idGarden]);
});

test("listReservationsForBranch: pagination — pageSize caps results and nextCursor advances correctly across pages, with no duplicate or skipped items", async () => {
  const organizationId = nextId("org");
  const branchId = nextId("branch");
  const base = new Date("2026-08-23T00:00:00.000Z").getTime();
  const ids: string[] = [];
  for (let i = 0; i < 5; i++) {
    ids.push(await seedReservation({ organizationId, branchId, requestedTime: new Date(base + i * 3_600_000) }));
  }
  const idToken = await mintStaffIdToken(organizationId, ["manager"]);

  const page1 = await callCallable(
    LIST_URL,
    {
      organizationId, branchId, pageSize: 2,
      dateFrom: new Date(base - 3_600_000).toISOString(),
      dateTo: new Date(base + 10 * 3_600_000).toISOString(),
    },
    idToken,
  );
  assert.strictEqual(page1.httpStatus, 200, JSON.stringify(page1.body));
  assert.deepStrictEqual(page1.body.result!.reservations.map((r) => r.id), [ids[0], ids[1]]);
  assert.ok(page1.body.result!.nextCursor, "expected a nextCursor for page 1");

  const page2 = await callCallable(
    LIST_URL,
    {
      organizationId, branchId, pageSize: 2, cursor: page1.body.result!.nextCursor,
      dateFrom: new Date(base - 3_600_000).toISOString(),
      dateTo: new Date(base + 10 * 3_600_000).toISOString(),
    },
    idToken,
  );
  assert.strictEqual(page2.httpStatus, 200, JSON.stringify(page2.body));
  assert.deepStrictEqual(page2.body.result!.reservations.map((r) => r.id), [ids[2], ids[3]]);

  const page3 = await callCallable(
    LIST_URL,
    {
      organizationId, branchId, pageSize: 2, cursor: page2.body.result!.nextCursor,
      dateFrom: new Date(base - 3_600_000).toISOString(),
      dateTo: new Date(base + 10 * 3_600_000).toISOString(),
    },
    idToken,
  );
  assert.strictEqual(page3.httpStatus, 200, JSON.stringify(page3.body));
  assert.deepStrictEqual(page3.body.result!.reservations.map((r) => r.id), [ids[4]]);
  assert.strictEqual(page3.body.result!.nextCursor, null);
});

test("listReservationsForBranch: cross-tenant fails closed — a caller authorized for org A cannot list org B's branch", async () => {
  const organizationIdA = nextId("org");
  const organizationIdB = nextId("org");
  const branchIdB = nextId("branch");
  await seedReservation({ organizationId: organizationIdB, branchId: branchIdB, requestedTime: new Date() });

  const idToken = await mintStaffIdToken(organizationIdA, ["manager"]);
  const result = await callCallable(
    LIST_URL,
    {
      organizationId: organizationIdA,
      branchId: branchIdB,
      dateFrom: new Date(Date.now() - 3_600_000).toISOString(),
      dateTo: new Date(Date.now() + 3_600_000).toISOString(),
    },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  // The query itself is branchId-scoped and would return org B's document,
  // but the structural organizationId check filters it back out.
  assert.deepStrictEqual(result.body.result!.reservations, []);
});

test("listReservationsForBranch: a caller without manageReservations is rejected", async () => {
  const organizationId = nextId("org");
  const branchId = nextId("branch");
  const idToken = await mintStaffIdToken(organizationId, ["staff"]);
  const result = await callCallable(
    LIST_URL,
    { organizationId, branchId, dateFrom: new Date().toISOString(), dateTo: new Date().toISOString() },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 403);
});

test("listReservationsForBranch: a date range wider than the maximum is rejected", async () => {
  const organizationId = nextId("org");
  const branchId = nextId("branch");
  const idToken = await mintStaffIdToken(organizationId, ["manager"]);
  const result = await callCallable(
    LIST_URL,
    {
      organizationId, branchId,
      dateFrom: "2026-01-01T00:00:00.000Z",
      dateTo: "2026-12-31T00:00:00.000Z",
    },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 400, JSON.stringify(result.body));
});

test("listReservationsForBranch: dateFrom after dateTo is rejected", async () => {
  const organizationId = nextId("org");
  const branchId = nextId("branch");
  const idToken = await mintStaffIdToken(organizationId, ["manager"]);
  const result = await callCallable(
    LIST_URL,
    {
      organizationId, branchId,
      dateFrom: "2026-08-25T00:00:00.000Z",
      dateTo: "2026-08-20T00:00:00.000Z",
    },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 400, JSON.stringify(result.body));
});

test("listReservationsForBranch: returns preorder/table/proposal-deadline indicators exactly as stored", async () => {
  const organizationId = nextId("org");
  const branchId = nextId("branch");
  const deadline = new Date("2026-08-24T18:00:00.000Z");
  const id = await seedReservation({
    organizationId, branchId, status: "changeProposed",
    requestedTime: new Date("2026-08-24T12:00:00.000Z"),
    assignedTableId: "table-7",
    preorderOrderId: "order-99",
    activeProposalCustomerResponseDeadlineAt: deadline,
  });

  const idToken = await mintStaffIdToken(organizationId, ["manager"]);
  const result = await callCallable(
    LIST_URL,
    {
      organizationId, branchId,
      dateFrom: "2026-08-24T00:00:00.000Z",
      dateTo: "2026-08-25T00:00:00.000Z",
    },
    idToken,
  );
  assert.strictEqual(result.httpStatus, 200, JSON.stringify(result.body));
  const item = result.body.result!.reservations.find((r) => r.id === id)!;
  assert.strictEqual(item.assignedTableId, "table-7");
  assert.strictEqual(item.preorderOrderId, "order-99");
  assert.strictEqual(item.activeProposalCustomerResponseDeadlineAt, deadline.toISOString());
});
