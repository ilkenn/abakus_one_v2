import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for the `setStandardIngredientCost` callable —
 * AP-5 Sprint 5. Mirrors `requestPrintJob.test.ts`'s established pattern:
 * raw HTTP against the callable wire protocol, staff identities minted via
 * anonymous sign-up + `setCustomUserClaims` + refresh-token.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SET_COST_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/setStandardIngredientCost`;

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
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
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
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, {
    organizationAccess: [organizationId],
    roles: { [organizationId]: roles },
  });
  return refreshIdToken(refreshToken);
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

test("setStandardIngredientCost: a manager can set a new cost, revision 1", async () => {
  const orgId = "org-1";
  const ingredientId = nextId("ingredient");
  const managerToken = await mintStaffIdToken(orgId, ["manager"]);

  const { body } = await callCallable(
    SET_COST_URL,
    { organizationId: orgId, ingredientId, unitCostAmountMinorUnits: 250, unitCode: "g" },
    managerToken,
  );
  assert.strictEqual(body.result?.revision, 1, JSON.stringify(body));

  const doc = await admin.firestore().collection("standardIngredientCosts").doc(`cost-${ingredientId}`).get();
  assert.strictEqual(doc.data()?.unitCostAmountMinorUnits, 250);
  assert.strictEqual(doc.data()?.unitCode, "g");
});

test("setStandardIngredientCost: a second call for the same ingredient upserts and increments revision", async () => {
  const orgId = "org-1";
  const ingredientId = nextId("ingredient");
  const managerToken = await mintStaffIdToken(orgId, ["manager"]);

  await callCallable(
    SET_COST_URL,
    { organizationId: orgId, ingredientId, unitCostAmountMinorUnits: 250, unitCode: "g" },
    managerToken,
  );
  const { body } = await callCallable(
    SET_COST_URL,
    { organizationId: orgId, ingredientId, unitCostAmountMinorUnits: 300, unitCode: "g" },
    managerToken,
  );
  assert.strictEqual(body.result?.revision, 2);

  const doc = await admin.firestore().collection("standardIngredientCosts").doc(`cost-${ingredientId}`).get();
  assert.strictEqual(doc.data()?.unitCostAmountMinorUnits, 300);
});

test("setStandardIngredientCost: staff-tier (no manageRecipes) is denied", async () => {
  const orgId = "org-1";
  const ingredientId = nextId("ingredient");
  const staffToken = await mintStaffIdToken(orgId, ["staff"]);

  const { body } = await callCallable(
    SET_COST_URL,
    { organizationId: orgId, ingredientId, unitCostAmountMinorUnits: 250, unitCode: "g" },
    staffToken,
  );
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("setStandardIngredientCost: a negative unitCostAmountMinorUnits is rejected as invalid-argument", async () => {
  const orgId = "org-1";
  const ingredientId = nextId("ingredient");
  const managerToken = await mintStaffIdToken(orgId, ["manager"]);

  const { body } = await callCallable(
    SET_COST_URL,
    { organizationId: orgId, ingredientId, unitCostAmountMinorUnits: -1, unitCode: "g" },
    managerToken,
  );
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});
