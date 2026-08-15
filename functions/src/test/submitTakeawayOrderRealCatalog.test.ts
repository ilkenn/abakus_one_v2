import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { readFileSync } from "fs";
import { join } from "path";
import { migrateCanonicalCatalog, type CatalogExport } from "../catalogMigration";

/**
 * Emulator-backed tests proving `submitTakeawayOrder` (Faz D.3) works
 * end-to-end against the REAL, fully-migrated menu catalog (Faz D.3.1) —
 * not just the synthetic fixtures `submitTakeawayOrder.test.ts` already
 * exhaustively covers (every precedence rule, every manipulation
 * scenario — not re-proven here). This file's job is narrower and
 * different: does the real exported `AbakusMenuCatalog`/
 * `LocalBowlBuilderCatalogRepository` data, once migrated, actually
 * price correctly through the real pricing pipeline — real product
 * shapes sometimes surface issues synthetic fixtures don't.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SUBMIT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/submitTakeawayOrder`;
const EXPORT_PATH = join(__dirname, "..", "..", "scripts", "data", "menu_catalog_export.json");

let app: admin.app.App;
let exportData: CatalogExport;
let sharedChain: { organizationId: string; restaurantId: string; branchId: string };

before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
  exportData = JSON.parse(readFileSync(EXPORT_PATH, "utf8")) as CatalogExport;
});

// Deliberately the SAME literal org/restaurant scope
// `catalogMigration.test.ts` uses for its own real-catalog migration: real
// product/ingredient document ids are global (`prod_mexifit_bowl`, ...),
// not per-test-scoped, so two test files independently migrating the real
// catalog under *different* scopes would race on those shared documents
// when `node --test` runs multiple files concurrently (each in its own
// process, against the one shared emulator) — this previously caused
// intermittent 400s ("product belongs to a different restaurant") here and
// empty query results there. Converging on identical scope values, and
// migrating the catalog only ONCE for this whole file (here, not per-test),
// means the shared documents' final content is always correct and
// consistent, regardless of interleaving with the other file's run.
before(async () => {
  sharedChain = await ensureSharedRealCatalogChain();
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

// Faz R.1C.1.1 — TEST_RUN_ID makes every generated id/phone number globally
// unique across the whole `node --test` invocation, not just within this
// file. Every test file's own counters previously started at 0, so two
// files could independently generate the identical `branch-87`/`area-88`
// string (or phone number) and silently share the same Firestore/Auth
// record across unrelated tests — a real, reproduced bug (root-caused via
// diagnostic capacity-bucket dumps showing a colliding chain's leftover
// data), not theoretical.
const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);

let phoneCounter = 0;
async function createRealPhoneUser(): Promise<{ idToken: string; uid: string }> {
  phoneCounter += 1;
  const phoneNumber = `+1555${PHONE_NAMESPACE}${String(phoneCounter).padStart(3, "0")}`;
  const sendRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ phoneNumber, recaptchaToken: "ignored-by-emulator" }),
    },
  );
  const sendBody = (await sendRes.json()) as { sessionInfo: string };
  const codesRes = await fetch(`${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`);
  const codesBody = (await codesRes.json()) as {
    verificationCodes: { sessionInfo: string; code: string }[];
  };
  const match = codesBody.verificationCodes.find((c) => c.sessionInfo === sendBody.sessionInfo)!;
  const signInRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }),
    },
  );
  const signInBody = (await signInRes.json()) as { idToken: string; localId: string };
  return { idToken: signInBody.idToken, uid: signInBody.localId };
}

async function createAnonymousUser(): Promise<{ idToken: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken: string };
  return { idToken: body.idToken };
}

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

function futurePickupIso(minutesFromNow: number): string {
  return new Date(Date.now() + minutesFromNow * 60 * 1000).toISOString();
}

const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz", contactPhone: "+905551112233" };

/**
 * The ONE shared org -> restaurant -> branch chain for this whole file,
 * with the REAL catalog migrated into it once. The real Faz A channel
 * pricing policy (+20 default, +0 İçecekler) is written by
 * `migrateCanonicalCatalog` itself (Faz D.3.1.1 — sourced from the export,
 * not hand-typed here a second time; see `catalogMigration.test.ts`'s own
 * dedicated coverage of that write). Idempotent (`.set()`-based,
 * deterministic ids) — safe to call from `before()` even if another
 * process/run has already seeded it.
 */
async function ensureSharedRealCatalogChain(): Promise<{
  organizationId: string;
  restaurantId: string;
  branchId: string;
}> {
  const db = admin.firestore();
  const chain = {
    organizationId: "real-catalog-shared-org",
    restaurantId: "real-catalog-shared-restaurant",
    branchId: "real-catalog-shared-branch",
  };

  await db.collection("organizations").doc(chain.organizationId).set({ name: "Test", isActive: true });
  await db
    .collection("restaurants")
    .doc(chain.restaurantId)
    .set({ organizationId: chain.organizationId, name: "Test", isActive: true });
  await db.collection("branches").doc(chain.branchId).set({
    restaurantId: chain.restaurantId,
    organizationId: chain.organizationId,
    name: "Merkez Şube",
    status: "active",
    emergencyStopped: false,
    supportedOrderChannelIds: ["takeaway"],
  });

  await migrateCanonicalCatalog(db, exportData, {
    organizationId: chain.organizationId,
    restaurantId: chain.restaurantId,
  });

  return chain;
}

/**
 * A second, genuinely separate org -> restaurant -> branch chain with NO
 * catalog migrated into it — only needed by the cross-tenant test, which
 * asserts on chain/scope mismatch, not on real product pricing, so it
 * doesn't need (and, to avoid the race described above, must not trigger)
 * another real-catalog migration.
 */
async function seedBareChain(): Promise<{ organizationId: string; restaurantId: string; branchId: string }> {
  const db = admin.firestore();
  const organizationId = nextId("real-org");
  const restaurantId = nextId("real-restaurant");
  const branchId = nextId("real-branch");

  await db.collection("organizations").doc(organizationId).set({ name: "Test", isActive: true });
  await db.collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  await db.collection("branches").doc(branchId).set({
    restaurantId,
    organizationId,
    name: "Merkez Şube",
    status: "active",
    emergencyStopped: false,
    supportedOrderChannelIds: ["takeaway"],
  });

  return { organizationId, restaurantId, branchId };
}

test("real catalog: an authenticated phone customer orders a real bowl product (prod_mexifit_bowl) — canonical price is basePrice + real Faz A +20 TL adjustment", async () => {
  const chain = sharedChain;
  const { idToken, uid } = await createRealPhoneUser();
  const mexifit = exportData.products.find((p) => p.id === "prod_mexifit_bowl")!;

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId: "prod_mexifit_bowl", quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.customerId, uid);
  assert.strictEqual(
    order.pricing.grandTotal.minorUnits,
    mexifit.basePriceMinorUnits + 2000,
    "real basePrice (430 TL) + real Faz A takeaway adjustment (+20 TL)",
  );
  assert.strictEqual(order.lines[0].productName, "Mexifit Bowl");
});

test("real catalog: a real İçecekler (beverage) product prices at basePrice unchanged (+0, real Faz A category override)", async () => {
  const chain = sharedChain;
  const { idToken } = await createRealPhoneUser();
  const drink = exportData.products.find((p) => p.categoryId === "cat_icecekler")!;

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId: drink.id, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.pricing.grandTotal.minorUnits, drink.basePriceMinorUnits);
});

test("real catalog: a bowl built from real, migrated Bowl Builder ingredients prices with the +20 TL channel adjustment applied exactly once, ingredient prices canonical", async () => {
  const chain = sharedChain;
  const { idToken } = await createRealPhoneUser();
  const protein = exportData.bowlIngredients.find((i) => i.categoryId === "protein")!;
  const carbs = exportData.bowlIngredients.find((i) => i.categoryId === "carbs")!;

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [
        {
          kind: "bowl",
          quantity: 1,
          ingredientIds: [protein.id, carbs.id],
        },
      ],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  const expectedIngredientTotal = protein.priceMinorUnits + carbs.priceMinorUnits;
  assert.strictEqual(order.lines[0].unitPrice.minorUnits, 2000, "the bowl's unitPrice is the +20 TL adjustment only");
  assert.strictEqual(order.pricing.grandTotal.minorUnits, expectedIngredientTotal + 2000);
});

test("real catalog: an explicit/fixed product-level override still takes precedence over the real Faz A default when layered onto the real catalog", async () => {
  const chain = sharedChain;
  const { idToken } = await createRealPhoneUser();

  // The real menu has zero products with a configured channelPriceOverrides
  // entry today (verified at export time) — this test seeds one
  // additional, test-only override product into the same real-catalog
  // restaurant to prove precedence composes correctly with real migrated
  // data, not just in isolation (already exhaustively covered by
  // `submitTakeawayOrder.test.ts`'s own synthetic-fixture tests).
  const overrideProductId = nextId("real-catalog-override-product");
  await admin.firestore().collection("menuProducts").doc(overrideProductId).set({
    organizationId: chain.organizationId,
    restaurantId: chain.restaurantId,
    categoryId: "cat_hamburger",
    name: "Test Override Ürünü",
    basePriceMinorUnits: 25000,
    isAvailable: true,
    modifierGroups: [],
    channelPriceOverrides: { takeaway: { type: "explicitPrice", priceMinorUnits: 59900 } },
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId: overrideProductId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 59900);
});

test("real catalog: an anonymous technical identity is denied even against a fully real, migrated catalog", async () => {
  const chain = sharedChain;
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId: "prod_mexifit_bowl", quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("real catalog: a wrong/nonexistent branchId is denied", async () => {
  const chain = sharedChain;
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: "branch-that-does-not-exist",
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId: "prod_mexifit_bowl", quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 404);
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});

test("real catalog: a cross-tenant branchId (belongs to a different restaurant) is denied", async () => {
  const chainA = sharedChain;
  const chainB = await seedBareChain();
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chainA.restaurantId,
      branchId: chainB.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId: "prod_mexifit_bowl", quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 404);
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});

test("real catalog: pickup time under 20 minutes is denied", async () => {
  const chain = sharedChain;
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(10),
      items: [{ kind: "product", productId: "prod_mexifit_bowl", quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});
