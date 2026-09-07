import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";

/**
 * Proves the real wiring, not just the isolated `enqueueKitchenWorkAndConsumeStock`
 * function (see `acceptOrderLine.test.ts` for that): calling the actual
 * `respondToDineInOrderLines` callable against a seeded `pendingApproval`
 * dine-in order really creates a `kitchenWorkItems` document and really
 * deducts `branchStock`, in the same request — AP-5 Sprint 2.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const RESPOND_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/respondToDineInOrderLines`;

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

async function mintStaffIdToken(
  organizationId: string,
  roles: string[],
  branchAccess: Record<string, string[]>,
): Promise<string> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, {
    organizationAccess: [organizationId],
    roles: { [organizationId]: roles },
    branchAccess,
  });
  return refreshIdToken(refreshToken);
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

test("respondToDineInOrderLines: accepting a line with a real RecipeIngredientLink really enqueues kitchen work and really deducts branchStock", async () => {
  const orgId = "org-1";
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const productId = nextId("product");
  const ingredientId = nextId("item");
  const orderLineId = `kt-${orderId}-line-0`;

  await admin.firestore().collection("inventoryItems").doc(ingredientId).set({
    organizationId: orgId,
    negativeStockPolicy: "allow",
  });
  await admin.firestore().collection("branchStock").doc(`${branchId}_${ingredientId}`).set({
    inventoryItemId: ingredientId,
    branchId,
    locationId: branchId,
    quantityOnHand: 100,
    isNegativeStockWarning: false,
    updatedAt: Timestamp.now(),
  });
  await admin.firestore().collection("recipeIngredientLinks").doc(`link-${productId}`).set({
    organizationId: orgId,
    productId,
    recipeVersionId: nextId("recipe-version"),
    ingredients: [{ inventoryItemId: ingredientId, quantitySmallestUnits: 20, unitCode: "g" }],
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    revision: 1,
  });

  await admin.firestore().collection("orders").doc(orderId).set({
    organizationId: orgId,
    branchId,
    channel: "dineInQr",
    mode: "guestSession",
    status: "pendingConfirmation",
    linesDispositionSummary: "pending",
    lines: [{ productId, quantity: 2, status: "pendingApproval" }],
  });

  const staffToken = await mintStaffIdToken(orgId, ["staff"], { [orgId]: [branchId] });
  const { body } = await callCallable(
    RESPOND_URL,
    { orderId, decisions: [{ lineIndex: 0, decision: "accept" }] },
    staffToken,
  );
  assert.strictEqual(body.result?.linesDispositionSummary, "resolved", JSON.stringify(body));

  const workItem = await admin.firestore().collection("kitchenWorkItems").doc(`kwi-${orderLineId}`).get();
  assert.strictEqual(workItem.exists, true);

  const stock = await admin.firestore().collection("branchStock").doc(`${branchId}_${ingredientId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 60); // 100 - (2 * 20g)
});

test("setRecipeIngredientLink: manager-tier can create and upsert a link; staff-tier is denied", async () => {
  const orgId = "org-1";
  const productId = nextId("product");
  const managerToken = await mintStaffIdToken(orgId, ["manager"], {});
  const staffToken = await mintStaffIdToken(orgId, ["staff"], {});

  const SET_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/setRecipeIngredientLink`;

  const denied = await callCallable(
    SET_URL,
    {
      organizationId: orgId,
      productId,
      recipeVersionId: "rv-1",
      ingredients: [{ inventoryItemId: "item-1", quantitySmallestUnits: 5, unitCode: "g" }],
    },
    staffToken,
  );
  assert.strictEqual(denied.body.error?.status, "PERMISSION_DENIED");

  const created = await callCallable(
    SET_URL,
    {
      organizationId: orgId,
      productId,
      recipeVersionId: "rv-1",
      ingredients: [{ inventoryItemId: "item-1", quantitySmallestUnits: 5, unitCode: "g" }],
    },
    managerToken,
  );
  assert.strictEqual(created.body.result?.revision, 1);

  const updated = await callCallable(
    SET_URL,
    {
      organizationId: orgId,
      productId,
      recipeVersionId: "rv-2",
      ingredients: [{ inventoryItemId: "item-1", quantitySmallestUnits: 8, unitCode: "g" }],
    },
    managerToken,
  );
  assert.strictEqual(updated.body.result?.revision, 2);
  assert.strictEqual(updated.body.result?.linkId, created.body.result?.linkId);
});

test("setProductPackagingLink: manager-tier can create a channel-specific packaging link; staff-tier is denied", async () => {
  const orgId = "org-1";
  const productId = nextId("product");
  const managerToken = await mintStaffIdToken(orgId, ["manager"], {});
  const staffToken = await mintStaffIdToken(orgId, ["staff"], {});

  const SET_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/setProductPackagingLink`;

  const denied = await callCallable(
    SET_URL,
    { organizationId: orgId, productId, channelCode: "takeaway", packagingInventoryItemId: "box-1", quantity: 1 },
    staffToken,
  );
  assert.strictEqual(denied.body.error?.status, "PERMISSION_DENIED");

  const created = await callCallable(
    SET_URL,
    { organizationId: orgId, productId, channelCode: "takeaway", packagingInventoryItemId: "box-1", quantity: 1 },
    managerToken,
  );
  assert.strictEqual(created.body.result?.revision, 1);
});
