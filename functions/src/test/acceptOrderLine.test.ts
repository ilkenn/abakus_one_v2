import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { prepareKitchenWorkAndStockConsumption, applyKitchenWorkAndStockConsumption } from "../acceptOrderLine";

/**
 * Direct, emulator-backed tests for `enqueueKitchenWorkAndConsumeStock` —
 * AP-5 Sprint 2. Tested by importing and invoking the exported function
 * directly inside a real `db.runTransaction`, rather than through the
 * full order-submission wire protocol — this is the shared internal
 * primitive itself (mirrors `applyOrderLifecycleTransition`'s own
 * "trusted internal primitive" shape, not a callable), so this is the
 * most direct way to exercise its idempotency/negative-stock/packaging
 * logic without needing full staff-entry/device-session order-submission
 * scaffolding for every case. The real wiring into `submitDineInOrder`/
 * `respondToDineInOrderLines`/`respondToTakeawayOrder`/
 * `respondToDeliveryOrder` is proven separately (see
 * `orderAcceptanceStockIntegration.test.ts`).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";

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

function db() {
  return admin.firestore();
}

async function seedRecipeLink(
  productId: string,
  ingredients: Array<{ inventoryItemId: string; quantitySmallestUnits: number; unitCode: string }>,
) {
  await db().collection("recipeIngredientLinks").doc(`link-${productId}`).set({
    organizationId: "org-1",
    productId,
    recipeVersionId: nextId("recipe-version"),
    ingredients,
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    revision: 1,
  });
}

async function seedPackagingLink(
  productId: string,
  channelCode: string,
  packagingInventoryItemId: string,
  quantity: number,
) {
  await db()
    .collection("productPackagingLinks")
    .doc(`link-${productId}-${channelCode}`)
    .set({
      organizationId: "org-1",
      productId,
      channelCode,
      packagingInventoryItemId,
      quantity,
      unitCode: "piece",
      createdAt: Timestamp.now(),
      updatedAt: Timestamp.now(),
      revision: 1,
    });
}

async function seedInventoryItem(inventoryItemId: string, negativeStockPolicy: "forbid" | "warn" | "allow") {
  await db().collection("inventoryItems").doc(inventoryItemId).set({
    organizationId: "org-1",
    negativeStockPolicy,
  });
}

async function seedBranchStock(branchId: string, inventoryItemId: string, quantityOnHand: number) {
  await db().collection("branchStock").doc(`${branchId}_${inventoryItemId}`).set({
    inventoryItemId,
    branchId,
    locationId: branchId,
    quantityOnHand,
    isNegativeStockWarning: false,
    updatedAt: Timestamp.now(),
  });
}

async function runAccept(params: {
  branchId: string;
  orderId: string;
  channel: string;
  acceptedLines: Array<{ orderLineId: string; productId: string; quantity: number }>;
}) {
  return db().runTransaction(async (tx) => {
    const plan = await prepareKitchenWorkAndStockConsumption({
      tx,
      db: db(),
      organizationId: "org-1",
      branchId: params.branchId,
      orderId: params.orderId,
      channel: params.channel,
      acceptedLines: params.acceptedLines,
      performedByUid: "staff-1",
      now: Timestamp.now(),
    });
    applyKitchenWorkAndStockConsumption(tx, db(), plan);
  });
}

test("enqueueKitchenWorkAndConsumeStock: a line with no RecipeIngredientLink still enqueues kitchen work but consumes nothing", async () => {
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const productId = nextId("product");
  const orderLineId = `${orderId}-line-0`;

  await runAccept({
    branchId,
    orderId,
    channel: "dineInQr",
    acceptedLines: [{ orderLineId, productId, quantity: 2 }],
  });

  const workItem = await db().collection("kitchenWorkItems").doc(`kwi-${orderLineId}`).get();
  assert.strictEqual(workItem.exists, true);
  assert.strictEqual(workItem.data()?.status, "queued");
  assert.strictEqual(workItem.data()?.organizationId, "org-1");

  const record = await db().collection("stockConsumptionRecords").doc(`accept-${orderId}-${orderLineId}`).get();
  assert.strictEqual(record.exists, true);
});

test("enqueueKitchenWorkAndConsumeStock: a linked recipe deducts the exact scaled quantity from branchStock and records a StockMovement", async () => {
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const productId = nextId("product");
  const ingredientId = nextId("item");
  const orderLineId = `${orderId}-line-0`;

  await seedInventoryItem(ingredientId, "allow");
  await seedBranchStock(branchId, ingredientId, 100);
  await seedRecipeLink(productId, [{ inventoryItemId: ingredientId, quantitySmallestUnits: 10, unitCode: "g" }]);

  await runAccept({
    branchId,
    orderId,
    channel: "dineInQr",
    acceptedLines: [{ orderLineId, productId, quantity: 3 }], // 3 * 10g = 30g
  });

  const stock = await db().collection("branchStock").doc(`${branchId}_${ingredientId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 70);

  const movements = await db().collection("stockMovements").where("relatedOrderId", "==", orderId).get();
  assert.strictEqual(movements.size, 1);
  assert.strictEqual(movements.docs[0].data().quantityDeltaSmallestUnits, -30);
});

test("enqueueKitchenWorkAndConsumeStock: a duplicate call for an already-processed line is a full no-op (idempotent) — no double kitchen item, no double deduction", async () => {
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const productId = nextId("product");
  const ingredientId = nextId("item");
  const orderLineId = `${orderId}-line-0`;

  await seedInventoryItem(ingredientId, "allow");
  await seedBranchStock(branchId, ingredientId, 100);
  await seedRecipeLink(productId, [{ inventoryItemId: ingredientId, quantitySmallestUnits: 10, unitCode: "g" }]);

  const params = {
    branchId,
    orderId,
    channel: "dineInQr",
    acceptedLines: [{ orderLineId, productId, quantity: 3 }],
  };
  await runAccept(params);
  await runAccept(params); // duplicate

  const stock = await db().collection("branchStock").doc(`${branchId}_${ingredientId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 70); // still 70, not 40

  const movements = await db().collection("stockMovements").where("relatedOrderId", "==", orderId).get();
  assert.strictEqual(movements.size, 1); // still exactly one movement
});

test("enqueueKitchenWorkAndConsumeStock: negativeStockPolicy 'forbid' rejects the whole call — no kitchen item, no movement, no partial deduction for ANY line", async () => {
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const productA = nextId("product");
  const productB = nextId("product");
  const ingredientId = nextId("item");
  const lineA = `${orderId}-line-0`;
  const lineB = `${orderId}-line-1`;

  await seedInventoryItem(ingredientId, "forbid");
  await seedBranchStock(branchId, ingredientId, 5);
  await seedRecipeLink(productA, [{ inventoryItemId: ingredientId, quantitySmallestUnits: 10, unitCode: "g" }]);
  // productB has no link — should still enqueue kitchen work in isolation,
  // but since it's in the SAME call as the forbidden line, the whole
  // transaction rejects, so productB's kitchen item must NOT exist either.

  await assert.rejects(
    runAccept({
      branchId,
      orderId,
      channel: "dineInQr",
      acceptedLines: [
        { orderLineId: lineA, productId: productA, quantity: 1 }, // needs 10g, only 5g on hand
        { orderLineId: lineB, productId: productB, quantity: 1 },
      ],
    }),
    /failed-precondition|Insufficient stock/,
  );

  const stock = await db().collection("branchStock").doc(`${branchId}_${ingredientId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 5); // unchanged

  const workItemA = await db().collection("kitchenWorkItems").doc(`kwi-${lineA}`).get();
  const workItemB = await db().collection("kitchenWorkItems").doc(`kwi-${lineB}`).get();
  assert.strictEqual(workItemA.exists, false);
  assert.strictEqual(workItemB.exists, false);
});

test("enqueueKitchenWorkAndConsumeStock: negativeStockPolicy 'warn' applies the movement and flags the resulting balance, never throws", async () => {
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const productId = nextId("product");
  const ingredientId = nextId("item");
  const orderLineId = `${orderId}-line-0`;

  await seedInventoryItem(ingredientId, "warn");
  await seedBranchStock(branchId, ingredientId, 5);
  await seedRecipeLink(productId, [{ inventoryItemId: ingredientId, quantitySmallestUnits: 10, unitCode: "g" }]);

  await runAccept({
    branchId,
    orderId,
    channel: "dineInQr",
    acceptedLines: [{ orderLineId, productId, quantity: 1 }],
  });

  const stock = await db().collection("branchStock").doc(`${branchId}_${ingredientId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, -5);
  assert.strictEqual(stock.data()?.isNegativeStockWarning, true);
});

test("enqueueKitchenWorkAndConsumeStock: an inventoryItem with no real InventoryItem document defaults to 'forbid' — the safe default when unconfigured", async () => {
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const productId = nextId("product");
  const ingredientId = nextId("item"); // deliberately never seeded via seedInventoryItem
  const orderLineId = `${orderId}-line-0`;

  await seedBranchStock(branchId, ingredientId, 5);
  await seedRecipeLink(productId, [{ inventoryItemId: ingredientId, quantitySmallestUnits: 10, unitCode: "g" }]);

  await assert.rejects(
    runAccept({
      branchId,
      orderId,
      channel: "dineInQr",
      acceptedLines: [{ orderLineId, productId, quantity: 1 }],
    }),
    /failed-precondition|Insufficient stock/,
  );
});

test("enqueueKitchenWorkAndConsumeStock: packaging consumption is channel-specific — the same product on a different channel consumes different (or no) packaging", async () => {
  const branchId = nextId("branch");
  const orderIdTakeaway = nextId("order");
  const orderIdDineIn = nextId("order");
  const productId = nextId("product");
  const boxId = nextId("packaging-item");

  await seedInventoryItem(boxId, "allow");
  await seedBranchStock(branchId, boxId, 50);
  await seedPackagingLink(productId, "takeaway", boxId, 1);
  // No packaging link for 'dineInQr' — dine-in uses reusable plateware.

  await runAccept({
    branchId,
    orderId: orderIdTakeaway,
    channel: "takeaway",
    acceptedLines: [{ orderLineId: `${orderIdTakeaway}-line-0`, productId, quantity: 4 }],
  });
  let stock = await db().collection("branchStock").doc(`${branchId}_${boxId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 46); // 50 - 4 boxes

  await runAccept({
    branchId,
    orderId: orderIdDineIn,
    channel: "dineInQr",
    acceptedLines: [{ orderLineId: `${orderIdDineIn}-line-0`, productId, quantity: 4 }],
  });
  stock = await db().collection("branchStock").doc(`${branchId}_${boxId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 46); // unchanged — no dine-in packaging link
});

test("enqueueKitchenWorkAndConsumeStock: the same ingredient consumed by two lines in one order is aggregated correctly, catching cumulative over-consumption", async () => {
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const productA = nextId("product");
  const productB = nextId("product");
  const ingredientId = nextId("item");
  const lineA = `${orderId}-line-0`;
  const lineB = `${orderId}-line-1`;

  await seedInventoryItem(ingredientId, "forbid");
  await seedBranchStock(branchId, ingredientId, 15);
  await seedRecipeLink(productA, [{ inventoryItemId: ingredientId, quantitySmallestUnits: 10, unitCode: "g" }]);
  await seedRecipeLink(productB, [{ inventoryItemId: ingredientId, quantitySmallestUnits: 10, unitCode: "g" }]);

  // Line A alone (10g) and line B alone (10g) each individually fit under
  // 15g, but together (20g) they don't — must be rejected, proving the
  // check aggregates across lines within the same call rather than
  // checking each line against the ORIGINAL balance independently.
  await assert.rejects(
    runAccept({
      branchId,
      orderId,
      channel: "dineInQr",
      acceptedLines: [
        { orderLineId: lineA, productId: productA, quantity: 1 },
        { orderLineId: lineB, productId: productB, quantity: 1 },
      ],
    }),
    /failed-precondition|Insufficient stock/,
  );

  const stock = await db().collection("branchStock").doc(`${branchId}_${ingredientId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 15); // unchanged, whole transaction rejected
});
