import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import { prepareKitchenWorkAndStockConsumption, applyKitchenWorkAndStockConsumption } from "../acceptOrderLine";
import { preparePrintJobForAcceptance, applyPrintJobPlan, derivePrintJobId } from "../printJobEngine";
import { prepareCancellationStockHandling, applyCancellationStockHandling } from "../cancelOrderLineStock";

/**
 * `ap5EndToEndLifecycle.test.ts` — AP-5 Sprint 6 (final sprint closure).
 *
 * Every individual primitive exercised here already has its own dedicated,
 * passing test file (`acceptOrderLine.test.ts`, `printJobEngine.test.ts`,
 * `stockCountReconciliation.test.ts`) — this file's value is proving all
 * five stages of the AP-5 lifecycle compose correctly against ONE
 * continuous order/branch/ingredient, catching integration-only bugs an
 * isolated unit test can't (e.g. a step silently assuming state a prior
 * step didn't actually leave behind). Stages 1-4 call the exported
 * prepare/apply primitives directly (mirrors `acceptOrderLine.test.ts`'s
 * own direct-invocation style); stage 5 goes through the real HTTP
 * callable wire protocol for `submitStockCount`/`respondToApprovalRequest`
 * (neither has a separately-exported pure function — the callable IS the
 * primitive), mirroring `stockCountReconciliation.test.ts`'s established
 * pattern.
 *
 * One shared ingredient/branch across every stage, with the on-hand
 * balance tracked explicitly at each step in the comments:
 *   1000 (seed) -> 990 (Order A accepted, 10g consumed)
 *   -> 980 (Order B accepted, 10g) -> 990 (Order B cancelled pre-prep, reversed)
 *   -> 980 (Order C accepted, 10g) -> 980 (Order C cancelled post-prep, wasted — not reversed)
 *   -> 900 (stock count: counted 900, manager-approved correction)
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SUBMIT_STOCK_COUNT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/submitStockCount`;
const RESPOND_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/respondToApprovalRequest`;

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

async function mintStaffIdToken(organizationId: string, roles: string[], branchAccess: Record<string, string[]>): Promise<string> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, {
    organizationAccess: [organizationId],
    roles: { [organizationId]: roles },
    branchAccess,
  });
  return refreshIdToken(refreshToken);
}

async function seedInventoryItem(inventoryItemId: string, ingredientId: string) {
  await db().collection("inventoryItems").doc(inventoryItemId).set({
    organizationId: "org-1",
    negativeStockPolicy: "forbid",
    ingredientId,
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

async function seedRecipeLink(productId: string, inventoryItemId: string, quantitySmallestUnits: number) {
  await db().collection("recipeIngredientLinks").doc(`link-${productId}`).set({
    organizationId: "org-1",
    productId,
    recipeVersionId: nextId("recipe-version"),
    ingredients: [{ inventoryItemId, quantitySmallestUnits, unitCode: "g" }],
    createdAt: Timestamp.now(),
    updatedAt: Timestamp.now(),
    revision: 1,
  });
}

async function seedStandardIngredientCost(ingredientId: string, unitCostAmountMinorUnits: number) {
  await db().collection("standardIngredientCosts").doc(`cost-${ingredientId}`).set({
    organizationId: "org-1",
    ingredientId,
    unitCostAmountMinorUnits,
    unitCode: "g",
  });
}

async function runAccept(branchId: string, orderId: string, orderLineId: string, productId: string) {
  return db().runTransaction(async (tx) => {
    const stockPlan = await prepareKitchenWorkAndStockConsumption({
      tx,
      db: db(),
      organizationId: "org-1",
      branchId,
      orderId,
      channel: "dineInQr",
      acceptedLines: [{ orderLineId, productId, quantity: 1 }],
      performedByUid: "staff-1",
      now: Timestamp.now(),
    });
    const printPlan = await preparePrintJobForAcceptance({
      tx,
      db: db(),
      organizationId: "org-1",
      branchId,
      orderId,
      stationId: "shared",
      now: Timestamp.now(),
    });
    applyKitchenWorkAndStockConsumption(tx, db(), stockPlan);
    applyPrintJobPlan(tx, db(), printPlan);
  });
}

async function currentBalance(branchId: string, inventoryItemId: string): Promise<number> {
  const snap = await db().collection("branchStock").doc(`${branchId}_${inventoryItemId}`).get();
  return snap.data()!.quantityOnHand as number;
}

test("AP-5 end-to-end: accept+cost -> print job -> pre-prep reversal -> post-prep waste -> stock count approval, all against one continuous branch/ingredient", async () => {
  const branchId = nextId("branch");
  const ingredientId = nextId("ingredient");
  const productId = nextId("product");

  await seedInventoryItem(ingredientId, ingredientId);
  await seedBranchStock(branchId, ingredientId, 1000);
  await seedRecipeLink(productId, ingredientId, 10);
  await seedStandardIngredientCost(ingredientId, 50); // 50 minor units per gram

  // --- Stage 1: order A accepted -> stock deducted + cost snapshot ---
  const orderA = nextId("order");
  const lineA = `${orderA}-line-0`;
  await runAccept(branchId, orderA, lineA, productId);

  assert.strictEqual(await currentBalance(branchId, ingredientId), 990);
  const workItemA = await db().collection("kitchenWorkItems").doc(`kwi-${lineA}`).get();
  assert.strictEqual(workItemA.data()?.status, "queued");
  const movementsA = await db().collection("stockMovements").where("relatedOrderId", "==", orderA).get();
  assert.strictEqual(movementsA.size, 1);
  assert.strictEqual(movementsA.docs[0].data().costSnapshotAmountMinorUnits, 500); // 50 * 10g

  // --- Stage 2: print job opened idempotently for order A ---
  const printJobId = derivePrintJobId(orderA, "shared", 0);
  const printJobA = await db().collection("printJobs").doc(printJobId).get();
  assert.strictEqual(printJobA.exists, true);
  assert.strictEqual(printJobA.data()?.status, "pending");

  // A second acceptance-path call for the same order must never open a
  // second print job (idempotent) — simulated directly via the prepare
  // primitive, mirroring what a retried acceptance transaction would do.
  const duplicatePrintPlan = await db().runTransaction((tx) =>
    preparePrintJobForAcceptance({
      tx, db: db(), organizationId: "org-1", branchId, orderId: orderA, stationId: "shared", now: Timestamp.now(),
    }),
  );
  assert.strictEqual(duplicatePrintPlan, null);

  // --- Stage 3: order B accepted then cancelled pre-prep -> reversed ---
  const orderB = nextId("order");
  const lineB = `${orderB}-line-0`;
  await runAccept(branchId, orderB, lineB, productId);
  assert.strictEqual(await currentBalance(branchId, ingredientId), 980);

  await db().runTransaction(async (tx) => {
    const plan = await prepareCancellationStockHandling({
      tx, db: db(), organizationId: "org-1", branchId, orderId: orderB, orderLineIds: [lineB],
      performedByUid: "staff-1", now: Timestamp.now(),
    });
    applyCancellationStockHandling(tx, db(), plan);
  });

  assert.strictEqual(await currentBalance(branchId, ingredientId), 990);
  const workItemB = await db().collection("kitchenWorkItems").doc(`kwi-${lineB}`).get();
  assert.strictEqual(workItemB.data()?.status, "cancelled");
  const reversalMovements = await db()
    .collection("stockMovements")
    .where("relatedOrderId", "==", orderB)
    .where("type", "==", "reversal")
    .get();
  assert.strictEqual(reversalMovements.size, 1);

  // --- Stage 4: order C accepted, advanced to preparing, then cancelled -> wasted ---
  const orderC = nextId("order");
  const lineC = `${orderC}-line-0`;
  await runAccept(branchId, orderC, lineC, productId);
  assert.strictEqual(await currentBalance(branchId, ingredientId), 980);

  const workItemCRef = db().collection("kitchenWorkItems").doc(`kwi-${lineC}`);
  await workItemCRef.update({ status: "preparing" });

  await db().runTransaction(async (tx) => {
    const plan = await prepareCancellationStockHandling({
      tx, db: db(), organizationId: "org-1", branchId, orderId: orderC, orderLineIds: [lineC],
      performedByUid: "staff-1", now: Timestamp.now(),
    });
    applyCancellationStockHandling(tx, db(), plan);
  });

  // Waste does NOT reverse stock — stays at 980, not back to 990.
  assert.strictEqual(await currentBalance(branchId, ingredientId), 980);
  const workItemC = await workItemCRef.get();
  assert.strictEqual(workItemC.data()?.status, "wasted");
  const wasteRecords = await db().collection("wasteRecords").where("orderId", "==", orderC).get();
  assert.strictEqual(wasteRecords.size, 1);
  assert.strictEqual(wasteRecords.docs[0].data().quantitySmallestUnits, 10);

  // --- Stage 5: physical stock count finds 900 (variance -80) -> manager approval -> correction ---
  const staffToken = await mintStaffIdToken("org-1", ["staff"], { "org-1": [branchId] });
  const managerToken = await mintStaffIdToken("org-1", ["manager"], { "org-1": [branchId] });

  const submitted = await callCallable(
    SUBMIT_STOCK_COUNT_URL,
    {
      organizationId: "org-1",
      branchId,
      locationId: branchId,
      countedItems: [{ inventoryItemId: ingredientId, countedQuantitySmallestUnits: 900, unitCode: "g" }],
    },
    staffToken,
  );
  assert.strictEqual(submitted.body.result?.status, "submitted", JSON.stringify(submitted.body));
  const approvalRequestId = submitted.body.result!.approvalRequestId as string;
  assert.ok(approvalRequestId);

  // Not yet corrected — approval is still pending.
  assert.strictEqual(await currentBalance(branchId, ingredientId), 980);

  const approved = await callCallable(RESPOND_URL, { requestId: approvalRequestId, decision: "approved" }, managerToken);
  assert.strictEqual(approved.body.result?.status, "approved", JSON.stringify(approved.body));

  assert.strictEqual(await currentBalance(branchId, ingredientId), 900);
  const countDoc = await db().collection("stockCounts").doc(submitted.body.result!.countId as string).get();
  assert.strictEqual(countDoc.data()?.status, "approved");
  const auditEntries = await db()
    .collection("inventoryAuditEntries")
    .where("targetEntityId", "==", submitted.body.result!.countId)
    .get();
  assert.strictEqual(auditEntries.size, 1);
  assert.strictEqual(auditEntries.docs[0].data().type, "stockCountApproved");

  const correctionMovements = await db()
    .collection("stockMovements")
    .where("correlationId", "==", submitted.body.result!.countId)
    .where("type", "==", "countCorrection")
    .get();
  assert.strictEqual(correctionMovements.size, 1);
  assert.strictEqual(correctionMovements.docs[0].data().quantityDeltaSmallestUnits, -80); // 900 - 980
});
