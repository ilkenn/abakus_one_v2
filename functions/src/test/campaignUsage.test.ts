import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import {
  reserveCampaignUsage,
  releaseCampaignUsage,
  CAMPAIGN_USAGE_COUNTERS_COLLECTION,
  CAMPAIGN_CUSTOMER_USAGE_COLLECTION,
  CAMPAIGN_USAGE_RESERVATIONS_COLLECTION,
} from "../campaignUsage";

/**
 * Emulator-backed tests for `campaignUsage.ts`'s transactional
 * reserve/release primitives — Server-Authoritative Campaign Engine P8-B
 * (2026-08-25). These are the race-safety proofs for the locked
 * requirement "two concurrent orders must not exceed a campaign's
 * remaining usage allowance."
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";

let app: admin.app.App;
before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});
after(async () => {
  await app.delete();
});

const db = () => admin.firestore();

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function reserveOnce(params: Parameters<typeof reserveCampaignUsage>[2]) {
  return db().runTransaction((tx) => reserveCampaignUsage(db(), tx, params));
}

async function releaseOnce(params: Parameters<typeof releaseCampaignUsage>[2]) {
  return db().runTransaction((tx) => releaseCampaignUsage(db(), tx, params));
}

async function counterCount(organizationId: string, campaignId: string): Promise<number> {
  const snap = await db()
    .collection(CAMPAIGN_USAGE_COUNTERS_COLLECTION)
    .doc(`${organizationId}_${campaignId}`)
    .get();
  return snap.exists ? ((snap.data()!.usageCount as number) ?? 0) : 0;
}

async function customerCount(organizationId: string, campaignId: string, customerId: string): Promise<number> {
  const snap = await db()
    .collection(CAMPAIGN_CUSTOMER_USAGE_COLLECTION)
    .doc(`${organizationId}_${campaignId}_${customerId}`)
    .get();
  return snap.exists ? ((snap.data()!.usageCount as number) ?? 0) : 0;
}

// =========================================================================
// A. reserveCampaignUsage — basic behavior
// =========================================================================

test("reserveCampaignUsage: first reservation succeeds, increments the global counter to 1", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  const orderId = nextId("order");

  const result = await reserveOnce({
    organizationId,
    campaignId,
    customerId: null,
    orderId,
    usageLimit: null,
    perCustomerUsageLimit: null,
  });
  assert.deepStrictEqual(result, { status: "reserved" });
  assert.strictEqual(await counterCount(organizationId, campaignId), 1);
});

test("reserveCampaignUsage: a retried submission with the same orderId is idempotent — never a second count", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  const orderId = nextId("order");
  const params = {
    organizationId,
    campaignId,
    customerId: null,
    orderId,
    usageLimit: null,
    perCustomerUsageLimit: null,
  };

  const first = await reserveOnce(params);
  const second = await reserveOnce(params);
  assert.deepStrictEqual(first, { status: "reserved" });
  assert.deepStrictEqual(second, { status: "already-reserved" });
  assert.strictEqual(await counterCount(organizationId, campaignId), 1);
});

test("reserveCampaignUsage: customerId null never creates a campaignCustomerUsage document — anonymous guest never per-customer-tracked", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  const orderId = nextId("order");

  await reserveOnce({
    organizationId,
    campaignId,
    customerId: null,
    orderId,
    usageLimit: null,
    perCustomerUsageLimit: null,
  });

  const allCustomerDocs = await db()
    .collection(CAMPAIGN_CUSTOMER_USAGE_COLLECTION)
    .where("organizationId", "==", organizationId)
    .where("campaignId", "==", campaignId)
    .get();
  assert.strictEqual(allCustomerDocs.size, 0);
});

test("reserveCampaignUsage: a real customerId increments BOTH the global and the per-customer counter", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  const customerId = nextId("customer");
  const orderId = nextId("order");

  await reserveOnce({
    organizationId,
    campaignId,
    customerId,
    orderId,
    usageLimit: null,
    perCustomerUsageLimit: null,
  });

  assert.strictEqual(await counterCount(organizationId, campaignId), 1);
  assert.strictEqual(await customerCount(organizationId, campaignId, customerId), 1);
});

// =========================================================================
// B. Global usage limit
// =========================================================================

test("reserveCampaignUsage: rejects once the global usage limit is reached", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");

  await reserveOnce({
    organizationId,
    campaignId,
    customerId: null,
    orderId: nextId("order"),
    usageLimit: 1,
    perCustomerUsageLimit: null,
  });
  const second = await reserveOnce({
    organizationId,
    campaignId,
    customerId: null,
    orderId: nextId("order"),
    usageLimit: 1,
    perCustomerUsageLimit: null,
  });
  assert.deepStrictEqual(second, { status: "global-limit-reached" });
  assert.strictEqual(await counterCount(organizationId, campaignId), 1);
});

test("reserveCampaignUsage: null usageLimit means unlimited — many reservations all succeed", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  for (let i = 0; i < 5; i++) {
    const result = await reserveOnce({
      organizationId,
      campaignId,
      customerId: null,
      orderId: nextId("order"),
      usageLimit: null,
      perCustomerUsageLimit: null,
    });
    assert.strictEqual(result.status, "reserved");
  }
  assert.strictEqual(await counterCount(organizationId, campaignId), 5);
});

// =========================================================================
// C. Per-customer usage limit
// =========================================================================

test("reserveCampaignUsage: rejects once a SPECIFIC customer's own limit is reached, unaffected by a DIFFERENT customer's usage", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  const customerA = nextId("customer");
  const customerB = nextId("customer");

  await reserveOnce({
    organizationId,
    campaignId,
    customerId: customerA,
    orderId: nextId("order"),
    usageLimit: null,
    perCustomerUsageLimit: 1,
  });
  const customerARetry = await reserveOnce({
    organizationId,
    campaignId,
    customerId: customerA,
    orderId: nextId("order"),
    usageLimit: null,
    perCustomerUsageLimit: 1,
  });
  assert.deepStrictEqual(customerARetry, { status: "customer-limit-reached" });

  const customerBFirst = await reserveOnce({
    organizationId,
    campaignId,
    customerId: customerB,
    orderId: nextId("order"),
    usageLimit: null,
    perCustomerUsageLimit: 1,
  });
  assert.deepStrictEqual(customerBFirst, { status: "reserved" });
});

// =========================================================================
// D. Concurrency — the actual race-safety proof
// =========================================================================

test("reserveCampaignUsage: N concurrent reservations against a global limit of K — exactly K succeed, never more", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  const usageLimit = 3;
  const attempts = 10;

  const results = await Promise.all(
    Array.from({ length: attempts }, () =>
      reserveOnce({
        organizationId,
        campaignId,
        customerId: null,
        orderId: nextId("order"),
        usageLimit,
        perCustomerUsageLimit: null,
      }),
    ),
  );

  const succeeded = results.filter((r) => r.status === "reserved").length;
  const rejected = results.filter((r) => r.status === "global-limit-reached").length;
  assert.strictEqual(succeeded, usageLimit, "exactly usageLimit reservations must succeed, never fewer or more");
  assert.strictEqual(rejected, attempts - usageLimit);
  assert.strictEqual(await counterCount(organizationId, campaignId), usageLimit);
});

test("reserveCampaignUsage: N concurrent reservations for the SAME customer against a per-customer limit of K — exactly K succeed", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  const customerId = nextId("customer");
  const perCustomerUsageLimit = 2;
  const attempts = 8;

  const results = await Promise.all(
    Array.from({ length: attempts }, () =>
      reserveOnce({
        organizationId,
        campaignId,
        customerId,
        orderId: nextId("order"),
        usageLimit: null,
        perCustomerUsageLimit,
      }),
    ),
  );

  const succeeded = results.filter((r) => r.status === "reserved").length;
  assert.strictEqual(succeeded, perCustomerUsageLimit);
  assert.strictEqual(await customerCount(organizationId, campaignId, customerId), perCustomerUsageLimit);
});

// =========================================================================
// E. releaseCampaignUsage
// =========================================================================

test("releaseCampaignUsage: decrements both the global and per-customer counter, marks the reservation released", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  const customerId = nextId("customer");
  const orderId = nextId("order");

  await reserveOnce({
    organizationId,
    campaignId,
    customerId,
    orderId,
    usageLimit: null,
    perCustomerUsageLimit: null,
  });
  assert.strictEqual(await counterCount(organizationId, campaignId), 1);

  const result = await releaseOnce({ organizationId, campaignId, orderId });
  assert.deepStrictEqual(result, { status: "released" });
  assert.strictEqual(await counterCount(organizationId, campaignId), 0);
  assert.strictEqual(await customerCount(organizationId, campaignId, customerId), 0);
});

test("releaseCampaignUsage: idempotent — a duplicate release never double-decrements", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  const orderId = nextId("order");

  await reserveOnce({
    organizationId,
    campaignId,
    customerId: null,
    orderId,
    usageLimit: null,
    perCustomerUsageLimit: null,
  });
  const first = await releaseOnce({ organizationId, campaignId, orderId });
  const second = await releaseOnce({ organizationId, campaignId, orderId });
  assert.deepStrictEqual(first, { status: "released" });
  assert.deepStrictEqual(second, { status: "already-released" });
  // A double-release must never take the counter below zero.
  assert.strictEqual(await counterCount(organizationId, campaignId), 0);
});

test("releaseCampaignUsage: releasing an order that never reserved anything is a clean no-op", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  const result = await releaseOnce({ organizationId, campaignId, orderId: nextId("order") });
  assert.deepStrictEqual(result, { status: "no-reservation-found" });
});

test("releaseCampaignUsage: freeing a reserved slot allows a new reservation to succeed under a global limit of 1", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  const firstOrderId = nextId("order");

  const first = await reserveOnce({
    organizationId,
    campaignId,
    customerId: null,
    orderId: firstOrderId,
    usageLimit: 1,
    perCustomerUsageLimit: null,
  });
  assert.strictEqual(first.status, "reserved");

  const blocked = await reserveOnce({
    organizationId,
    campaignId,
    customerId: null,
    orderId: nextId("order"),
    usageLimit: 1,
    perCustomerUsageLimit: null,
  });
  assert.strictEqual(blocked.status, "global-limit-reached");

  await releaseOnce({ organizationId, campaignId, orderId: firstOrderId });

  const afterRelease = await reserveOnce({
    organizationId,
    campaignId,
    customerId: null,
    orderId: nextId("order"),
    usageLimit: 1,
    perCustomerUsageLimit: null,
  });
  assert.strictEqual(afterRelease.status, "reserved");
});

test("reservation document is keyed deterministically by (organizationId, campaignId, orderId)", async () => {
  const organizationId = nextId("org");
  const campaignId = nextId("camp");
  const orderId = nextId("order");
  await reserveOnce({
    organizationId,
    campaignId,
    customerId: null,
    orderId,
    usageLimit: null,
    perCustomerUsageLimit: null,
  });
  const snap = await db()
    .collection(CAMPAIGN_USAGE_RESERVATIONS_COLLECTION)
    .doc(`${organizationId}_${campaignId}_${orderId}`)
    .get();
  assert.strictEqual(snap.exists, true);
  assert.strictEqual(snap.data()!.status, "reserved");
});
