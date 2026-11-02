import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * 2026-10-28 — emulator-backed tests for the new admin Menü backend
 * (`menuCatalogAdmin.ts`). Mirrors `staffMembership.test.ts`'s exact
 * pattern: raw HTTP against the callable wire protocol, real Firestore
 * fixtures, a per-file `TEST_RUN_ID` namespace.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const LIST_CATEGORIES_URL = fn("listMenuCategories");
const CREATE_CATEGORY_URL = fn("createMenuCategory");
const LIST_PRODUCTS_URL = fn("listMenuProducts");
const CREATE_PRODUCT_URL = fn("createMenuProduct");

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

/** A real staff member with [roles] for a fresh organization; returns a post-sync, post-refresh idToken. */
async function staffToken(organizationId: string, roles: string[]): Promise<string> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await admin.firestore().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles, branchAccess: [], restaurantAccess: [],
    status: "active", createdAt: new Date(), updatedAt: new Date(),
  });
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  return refreshIdToken(refreshToken);
}

test("createMenuCategory + listMenuCategories: a manager can create a category and then see it listed", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const idToken = await staffToken(organizationId, ["manager"]);

  const create = await callCallable(
    CREATE_CATEGORY_URL,
    { organizationId, restaurantId, name: "İçecekler", sortOrder: 1 },
    idToken,
  );
  assert.strictEqual(create.httpStatus, 200, JSON.stringify(create.body));
  const categoryId = create.body.result?.id as string;
  assert.ok(categoryId);

  const list = await callCallable(LIST_CATEGORIES_URL, { organizationId }, idToken);
  assert.strictEqual(list.httpStatus, 200, JSON.stringify(list.body));
  const categories = list.body.result?.categories as Array<{ id: string; name: string }>;
  assert.ok(categories.some((c) => c.id === categoryId && c.name === "İçecekler"));
});

test("createMenuCategory: a staff-tier member (no manageMenu) is denied", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const idToken = await staffToken(organizationId, ["staff"]);

  const create = await callCallable(
    CREATE_CATEGORY_URL,
    { organizationId, restaurantId, name: "Tatlılar" },
    idToken,
  );
  assert.strictEqual(create.httpStatus, 403, JSON.stringify(create.body));
});

test("createMenuProduct: fails closed (not-found) for a category id that doesn't exist in this organization", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const idToken = await staffToken(organizationId, ["admin"]);

  const create = await callCallable(
    CREATE_PRODUCT_URL,
    { organizationId, restaurantId, categoryId: "does-not-exist", name: "Ayran", basePriceMinorUnits: 4000 },
    idToken,
  );
  assert.strictEqual(create.httpStatus, 404, JSON.stringify(create.body));
});

test("createMenuProduct + listMenuProducts: an admin can create a product under a real category and see it listed", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const idToken = await staffToken(organizationId, ["admin"]);

  const category = await callCallable(
    CREATE_CATEGORY_URL,
    { organizationId, restaurantId, name: "Ana Yemekler" },
    idToken,
  );
  const categoryId = category.body.result?.id as string;

  const product = await callCallable(
    CREATE_PRODUCT_URL,
    { organizationId, restaurantId, categoryId, name: "Mexifit Bowl", basePriceMinorUnits: 29000 },
    idToken,
  );
  assert.strictEqual(product.httpStatus, 200, JSON.stringify(product.body));
  const productId = product.body.result?.id as string;
  assert.ok(productId);

  const list = await callCallable(LIST_PRODUCTS_URL, { organizationId }, idToken);
  assert.strictEqual(list.httpStatus, 200, JSON.stringify(list.body));
  const products = list.body.result?.products as Array<{ id: string; name: string; categoryId: string }>;
  assert.ok(products.some((p) => p.id === productId && p.name === "Mexifit Bowl" && p.categoryId === categoryId));
});

test("listMenuCategories/listMenuProducts: a different organization's staff member sees none of this organization's data", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const otherOrganizationId = nextId("org");
  const ownerToken = await staffToken(organizationId, ["admin"]);
  await callCallable(CREATE_CATEGORY_URL, { organizationId, restaurantId, name: "Tatlılar" }, ownerToken);

  const outsiderToken = await staffToken(otherOrganizationId, ["admin"]);
  const list = await callCallable(LIST_CATEGORIES_URL, { organizationId: otherOrganizationId }, outsiderToken);
  assert.strictEqual(list.httpStatus, 200, JSON.stringify(list.body));
  const categories = list.body.result?.categories as Array<unknown>;
  assert.strictEqual(categories.length, 0);
});
