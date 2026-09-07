import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { prepareCancellationStockHandling, applyCancellationStockHandling } from "../cancelOrderLineStock";

/**
 * Direct, emulator-backed tests for `cancelOrderLineStock.ts` — AP-5
 * Sprint 3. Mirrors `acceptOrderLine.test.ts`'s pattern: the shared
 * internal `prepare`/`apply` functions are imported and invoked directly
 * inside a real `db.runTransaction`, seeding the fixtures
 * `enqueueKitchenWorkAndConsumeStock` would itself have produced
 * (`stockConsumptionRecords`, `kitchenWorkItems`, `stockMovements`) via
 * the Admin SDK. The real wiring into `applyAcceptedLineCancellation`/
 * `cancelTakeawayOrderForStaff`/`cancelDeliveryOrderForStaff` is exercised
 * by those files' own existing test suites (`takeawayOrderLifecycle
 * .test.ts` et al.), which this sprint's full-suite run proves are still
 * green.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";

let app: admin.app.App;
before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});
after(async () => {
  await app.delete();
});

function db() {
  return admin.firestore();
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function seedConsumedLine(fields: {
  branchId: string;
  orderId: string;
  orderLineId: string;
  workItemStatus: string;
  ingredientId: string;
  ingredientQuantity: number;
  packagingId?: string;
  packagingQuantity?: number;
  branchStockBefore: Record<string, number>;
}) {
  const { branchId, orderId, orderLineId, workItemStatus, ingredientId, ingredientQuantity, packagingId, packagingQuantity, branchStockBefore } = fields;

  await db().collection("stockConsumptionRecords").doc(`accept-${orderId}-${orderLineId}`).set({
    organizationId: "org-1",
    branchId,
    orderId,
    orderLineId,
    productId: nextId("product"),
    consumedAt: Timestamp.now(),
    disposition: "consumed",
  });

  await db().collection("kitchenWorkItems").doc(`kwi-${orderLineId}`).set({
    organizationId: "org-1",
    branchId,
    orderId,
    status: workItemStatus,
    revision: 3,
  });

  await db().collection("stockMovements").doc(`move-${orderId}-${orderLineId}-${ingredientId}-0`).set({
    organizationId: "org-1",
    branchId,
    inventoryItemId: ingredientId,
    locationId: branchId,
    type: "consumption",
    quantityDeltaSmallestUnits: -ingredientQuantity,
    unitCode: "g",
    relatedOrderId: orderId,
    correlationId: orderLineId,
    occurredAt: Timestamp.now(),
  });

  if (packagingId && packagingQuantity) {
    await db().collection("stockMovements").doc(`move-${orderId}-${orderLineId}-${packagingId}-1`).set({
      organizationId: "org-1",
      branchId,
      inventoryItemId: packagingId,
      locationId: branchId,
      type: "consumption",
      quantityDeltaSmallestUnits: -packagingQuantity,
      unitCode: "piece",
      relatedOrderId: orderId,
      correlationId: orderLineId,
      occurredAt: Timestamp.now(),
    });
  }

  for (const [itemId, balance] of Object.entries(branchStockBefore)) {
    await db().collection("branchStock").doc(`${branchId}_${itemId}`).set({
      inventoryItemId: itemId,
      branchId,
      locationId: branchId,
      quantityOnHand: balance,
      updatedAt: Timestamp.now(),
    });
  }
}

async function runCancel(params: { branchId: string; orderId: string; orderLineIds: string[] }) {
  return db().runTransaction(async (tx) => {
    const plan = await prepareCancellationStockHandling({
      tx,
      db: db(),
      organizationId: "org-1",
      branchId: params.branchId,
      orderId: params.orderId,
      orderLineIds: params.orderLineIds,
      performedByUid: "staff-1",
      now: Timestamp.now(),
    });
    applyCancellationStockHandling(tx, db(), plan);
  });
}

test("cancelOrderLineStock: a queued line's consumed stock is fully reversed and the work item cancels", async () => {
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const orderLineId = `${orderId}-line-0`;
  const ingredientId = nextId("item");

  await seedConsumedLine({
    branchId, orderId, orderLineId, workItemStatus: "queued",
    ingredientId, ingredientQuantity: 30,
    branchStockBefore: { [ingredientId]: 70 },
  });

  await runCancel({ branchId, orderId, orderLineIds: [orderLineId] });

  const stock = await db().collection("branchStock").doc(`${branchId}_${ingredientId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 100); // 70 + 30 returned

  const workItem = await db().collection("kitchenWorkItems").doc(`kwi-${orderLineId}`).get();
  assert.strictEqual(workItem.data()?.status, "cancelled");
  assert.strictEqual(workItem.data()?.revision, 4);

  const record = await db().collection("stockConsumptionRecords").doc(`accept-${orderId}-${orderLineId}`).get();
  assert.strictEqual(record.data()?.disposition, "reversed");

  const reversalMovements = await db()
    .collection("stockMovements")
    .where("relatedOrderId", "==", orderId)
    .where("type", "==", "reversal")
    .get();
  assert.strictEqual(reversalMovements.size, 1);
  assert.strictEqual(reversalMovements.docs[0].data().quantityDeltaSmallestUnits, 30);
});

test("cancelOrderLineStock: an acknowledged line also reverses (both pre-prep statuses behave the same)", async () => {
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const orderLineId = `${orderId}-line-0`;
  const ingredientId = nextId("item");

  await seedConsumedLine({
    branchId, orderId, orderLineId, workItemStatus: "acknowledged",
    ingredientId, ingredientQuantity: 10,
    branchStockBefore: { [ingredientId]: 5 },
  });

  await runCancel({ branchId, orderId, orderLineIds: [orderLineId] });

  const stock = await db().collection("branchStock").doc(`${branchId}_${ingredientId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 15);
});

test("cancelOrderLineStock: a preparing line is wasted, not reversed — branchStock untouched, wasteRecords written for ingredient AND packaging", async () => {
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const orderLineId = `${orderId}-line-0`;
  const ingredientId = nextId("item");
  const packagingId = nextId("packaging");

  await seedConsumedLine({
    branchId, orderId, orderLineId, workItemStatus: "preparing",
    ingredientId, ingredientQuantity: 20,
    packagingId, packagingQuantity: 1,
    branchStockBefore: { [ingredientId]: 80, [packagingId]: 49 },
  });

  await runCancel({ branchId, orderId, orderLineIds: [orderLineId] });

  const ingredientStock = await db().collection("branchStock").doc(`${branchId}_${ingredientId}`).get();
  assert.strictEqual(ingredientStock.data()?.quantityOnHand, 80); // unchanged — already correctly reduced
  const packagingStock = await db().collection("branchStock").doc(`${branchId}_${packagingId}`).get();
  assert.strictEqual(packagingStock.data()?.quantityOnHand, 49); // unchanged

  const workItem = await db().collection("kitchenWorkItems").doc(`kwi-${orderLineId}`).get();
  assert.strictEqual(workItem.data()?.status, "wasted");

  const wasteRecords = await db().collection("wasteRecords").where("orderId", "==", orderId).get();
  assert.strictEqual(wasteRecords.size, 2); // ingredient + packaging
  const wastedItemIds = wasteRecords.docs.map((d) => d.data().inventoryItemId).sort();
  assert.deepStrictEqual(wastedItemIds, [ingredientId, packagingId].sort());
  for (const doc of wasteRecords.docs) {
    assert.strictEqual(doc.data().reason, "customer_cancellation_after_prep");
  }

  const noReversalMovements = await db()
    .collection("stockMovements")
    .where("relatedOrderId", "==", orderId)
    .where("type", "==", "reversal")
    .get();
  assert.strictEqual(noReversalMovements.size, 0);
});

test("cancelOrderLineStock: a ready line is also wasted (not just preparing)", async () => {
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const orderLineId = `${orderId}-line-0`;
  const ingredientId = nextId("item");

  await seedConsumedLine({
    branchId, orderId, orderLineId, workItemStatus: "ready",
    ingredientId, ingredientQuantity: 5,
    branchStockBefore: { [ingredientId]: 95 },
  });

  await runCancel({ branchId, orderId, orderLineIds: [orderLineId] });

  const workItem = await db().collection("kitchenWorkItems").doc(`kwi-${orderLineId}`).get();
  assert.strictEqual(workItem.data()?.status, "wasted");
  const stock = await db().collection("branchStock").doc(`${branchId}_${ingredientId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 95);
});

test("cancelOrderLineStock: a duplicate cancellation call is a full no-op (idempotent) — no double reversal, no double waste record", async () => {
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const orderLineId = `${orderId}-line-0`;
  const ingredientId = nextId("item");

  await seedConsumedLine({
    branchId, orderId, orderLineId, workItemStatus: "queued",
    ingredientId, ingredientQuantity: 10,
    branchStockBefore: { [ingredientId]: 50 },
  });

  await runCancel({ branchId, orderId, orderLineIds: [orderLineId] });
  await runCancel({ branchId, orderId, orderLineIds: [orderLineId] }); // duplicate

  const stock = await db().collection("branchStock").doc(`${branchId}_${ingredientId}`).get();
  assert.strictEqual(stock.data()?.quantityOnHand, 60); // still 60, not 70

  const reversalMovements = await db()
    .collection("stockMovements")
    .where("relatedOrderId", "==", orderId)
    .where("type", "==", "reversal")
    .get();
  assert.strictEqual(reversalMovements.size, 1); // still exactly one
});

test("cancelOrderLineStock: a line with no kitchenWorkItem (no recipe/packaging link) cancels cleanly with no stock side effects", async () => {
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const orderLineId = `${orderId}-line-0`;

  await db().collection("stockConsumptionRecords").doc(`accept-${orderId}-${orderLineId}`).set({
    organizationId: "org-1",
    branchId,
    orderId,
    orderLineId,
    productId: nextId("product"),
    consumedAt: Timestamp.now(),
    disposition: "consumed",
  });

  await runCancel({ branchId, orderId, orderLineIds: [orderLineId] });

  const record = await db().collection("stockConsumptionRecords").doc(`accept-${orderId}-${orderLineId}`).get();
  assert.strictEqual(record.data()?.disposition, "wasted");
  const workItem = await db().collection("kitchenWorkItems").doc(`kwi-${orderLineId}`).get();
  assert.strictEqual(workItem.exists, false);
});

test("cancelOrderLineStock: cancelling multiple lines in one order (e.g. whole-order cancel) reverses and wastes independently per line", async () => {
  const branchId = nextId("branch");
  const orderId = nextId("order");
  const lineA = `${orderId}-line-0`;
  const lineB = `${orderId}-line-1`;
  const itemA = nextId("item");
  const itemB = nextId("item");

  await seedConsumedLine({
    branchId, orderId, orderLineId: lineA, workItemStatus: "queued",
    ingredientId: itemA, ingredientQuantity: 10,
    branchStockBefore: { [itemA]: 40 },
  });
  await seedConsumedLine({
    branchId, orderId, orderLineId: lineB, workItemStatus: "preparing",
    ingredientId: itemB, ingredientQuantity: 15,
    branchStockBefore: { [itemB]: 60 },
  });

  await runCancel({ branchId, orderId, orderLineIds: [lineA, lineB] });

  const stockA = await db().collection("branchStock").doc(`${branchId}_${itemA}`).get();
  assert.strictEqual(stockA.data()?.quantityOnHand, 50); // reversed

  const stockB = await db().collection("branchStock").doc(`${branchId}_${itemB}`).get();
  assert.strictEqual(stockB.data()?.quantityOnHand, 60); // unchanged (wasted)

  const workItemA = await db().collection("kitchenWorkItems").doc(`kwi-${lineA}`).get();
  const workItemB = await db().collection("kitchenWorkItems").doc(`kwi-${lineB}`).get();
  assert.strictEqual(workItemA.data()?.status, "cancelled");
  assert.strictEqual(workItemB.data()?.status, "wasted");
});
