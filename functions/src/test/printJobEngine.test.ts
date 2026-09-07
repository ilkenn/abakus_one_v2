import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { Timestamp } from "firebase-admin/firestore";
import {
  derivePrintJobId,
  preparePrintJobForAcceptance,
  applyPrintJobPlan,
  resolveMockPrintOutcome,
  processPrintJob,
} from "../printJobEngine";

/**
 * Direct, emulator-backed tests for `printJobEngine.ts` — AP-5 Sprint 4.
 * Mirrors `acceptOrderLine.test.ts`'s own pattern: import and invoke the
 * exported prepare/apply primitives directly inside a real
 * `db.runTransaction`, rather than through the full order-acceptance wire
 * protocol — the actual wiring into `submitDineInOrder`/
 * `respondToDineInOrderLines`/`respondToTakeawayOrder`/
 * `respondToDeliveryOrder` mirrors the already-tested
 * `prepareKitchenWorkAndStockConsumption`/`applyKitchenWorkAndStockConsumption`
 * call-site shape exactly (same read-before-write gating condition, same
 * transaction), so it is not re-proven with a second full-stack test here.
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

async function runPrepareAndApply(orderId: string, branchId: string, stationId = "shared") {
  return db().runTransaction(async (tx) => {
    const plan = await preparePrintJobForAcceptance({
      tx,
      db: db(),
      organizationId: "org-1",
      branchId,
      orderId,
      stationId,
      now: Timestamp.now(),
    });
    applyPrintJobPlan(tx, db(), plan);
    return plan;
  });
}

async function seedPrinterConfig(branchId: string, stationId: string) {
  await db().collection("printerConfigs").doc(nextId("printer")).set({
    organizationId: "org-1",
    branchId,
    stationId,
    transport: "network",
    isBackup: false,
  });
}

test("preparePrintJobForAcceptance: opens a pending job at the deterministic gen0 id", async () => {
  const orderId = nextId("order");
  const branchId = nextId("branch");

  const plan = await runPrepareAndApply(orderId, branchId);
  assert.ok(plan);
  assert.strictEqual(plan!.printJobId, derivePrintJobId(orderId, "shared", 0));

  const snap = await db().collection("printJobs").doc(plan!.printJobId).get();
  assert.strictEqual(snap.data()?.status, "pending");
  assert.strictEqual(snap.data()?.orderId, orderId);
  assert.strictEqual(snap.data()?.isCopy, false);
});

test("preparePrintJobForAcceptance: a duplicate/retried acceptance call is a pure no-op, never a second job", async () => {
  const orderId = nextId("order");
  const branchId = nextId("branch");

  const firstPlan = await runPrepareAndApply(orderId, branchId);
  assert.ok(firstPlan);

  const secondPlan = await runPrepareAndApply(orderId, branchId);
  assert.strictEqual(secondPlan, null);

  const snap = await db().collection("printJobs").doc(derivePrintJobId(orderId, "shared", 0)).get();
  assert.strictEqual(snap.data()?.status, "pending"); // untouched by the second call
});

test("resolveMockPrintOutcome: succeeds only when a printerConfigs document is registered for the (branch, station) pair", async () => {
  const branchId = nextId("branch");

  const beforeOutcome = await resolveMockPrintOutcome(db(), branchId, "shared");
  assert.strictEqual(beforeOutcome, "failed");

  await seedPrinterConfig(branchId, "shared");
  const afterOutcome = await resolveMockPrintOutcome(db(), branchId, "shared");
  assert.strictEqual(afterOutcome, "success");

  // A printer registered for a DIFFERENT station never satisfies this one.
  const otherStationOutcome = await resolveMockPrintOutcome(db(), branchId, "hot");
  assert.strictEqual(otherStationOutcome, "failed");
});

test("processPrintJob: drives a pending job through printing to a terminal status, observable at each step", async () => {
  const orderId = nextId("order");
  const branchId = nextId("branch");
  await seedPrinterConfig(branchId, "shared");
  const plan = await runPrepareAndApply(orderId, branchId);

  const outcome = await processPrintJob(db(), plan!.printJobId, branchId, "shared");
  assert.strictEqual(outcome, "success");

  const snap = await db().collection("printJobs").doc(plan!.printJobId).get();
  assert.strictEqual(snap.data()?.status, "success");
});

test("processPrintJob: no registered printer resolves to a terminal failed status", async () => {
  const orderId = nextId("order");
  const branchId = nextId("branch");
  const plan = await runPrepareAndApply(orderId, branchId);

  const outcome = await processPrintJob(db(), plan!.printJobId, branchId, "shared");
  assert.strictEqual(outcome, "failed");

  const snap = await db().collection("printJobs").doc(plan!.printJobId).get();
  assert.strictEqual(snap.data()?.status, "failed");
});
