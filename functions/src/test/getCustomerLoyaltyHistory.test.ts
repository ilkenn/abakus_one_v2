import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import {
  mapLedgerEntryToCustomerHistoryRow,
  type CustomerLoyaltyHistoryPage,
} from "../getCustomerLoyaltyHistory";

/**
 * Emulator-backed + pure-function tests for `getCustomerLoyaltyHistory` —
 * Boncuk Loyalty Program P3A (2026-08-23). Mirrors
 * `getCustomerLoyaltySnapshot.test.ts`'s exact identity/tenant test
 * pattern, plus `listReservationsForBranch.ts`'s pagination test shape.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const HISTORY_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/getCustomerLoyaltyHistory`;
const ORG = "org-1";

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
    result?: CustomerLoyaltyHistoryPage;
    error?: { status?: string; message?: string };
  };
  return { httpStatus: response.status, body };
}

async function createAnonymousUser(): Promise<{ idToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken: string; localId: string };
  return { idToken: body.idToken, uid: body.localId };
}

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
  const codesBody = (await codesRes.json()) as { verificationCodes: { sessionInfo: string; code: string }[] };
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

const db = () => admin.firestore();

async function seedTenantMembership(uid: string, organizationId: string = ORG) {
  await db().collection("tenantCustomers").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, createdAt: admin.firestore.Timestamp.now(),
  });
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let seq = 0;
const nextId = (prefix: string) => `${prefix}-${TEST_RUN_ID}-${++seq}`;

interface SeedEntryParams {
  organizationId?: string;
  customerId: string;
  entryType?: string;
  entitlementDeltaBoncuk?: number;
  spendableDeltaBoncuk?: number;
  debtDeltaBoncuk?: number;
  orderId?: string | null;
  createdAt?: admin.firestore.Timestamp;
}

async function seedLedgerEntry(params: SeedEntryParams): Promise<string> {
  const id = nextId("ledger");
  await db().collection("loyaltyLedgerEntries").doc(id).set({
    organizationId: params.organizationId ?? ORG,
    customerId: params.customerId,
    entryType: params.entryType ?? "orderEarn",
    entitlementDeltaBoncuk: params.entitlementDeltaBoncuk ?? 5,
    spendableDeltaBoncuk: params.spendableDeltaBoncuk ?? 5,
    debtDeltaBoncuk: params.debtDeltaBoncuk ?? 0,
    sourceId: params.orderId ?? id,
    orderId: params.orderId === undefined ? null : params.orderId,
    amountBasisMinorUnits: 25000,
    orderEligibleNetSpendBeforeMinorUnits: 0,
    orderEligibleNetSpendAfterMinorUnits: 25000,
    orderEntitlementBeforeBoncuk: 0,
    orderEntitlementAfterBoncuk: 5,
    remainderBeforeMinorUnits: 0,
    remainderAfterMinorUnits: 0,
    earningRateMinorUnitsPerBoncuk: 1000,
    debtBeforeBoncuk: 0,
    debtAfterBoncuk: 0,
    redemptionRateMinorUnitsPerBoncuk: null,
    idempotencyKey: id,
    reversalOf: null,
    expiresAt: null,
    metadata: null,
    createdAt: params.createdAt ?? admin.firestore.Timestamp.now(),
  });
  return id;
}

// =========================================================================
// A. Authentication / real-customer / tenant-membership gating
// =========================================================================

test("a guest (unauthenticated caller) is rejected", async () => {
  const { httpStatus, body } = await callCallable(HISTORY_URL, {});
  assert.strictEqual(httpStatus, 401);
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("an anonymous (non-phone) authenticated user is rejected", async () => {
  const { idToken } = await createAnonymousUser();
  const { httpStatus, body } = await callCallable(HISTORY_URL, {}, idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("a real phone customer with no tenantCustomers membership is denied", async () => {
  const { idToken } = await createRealPhoneUser();
  const { httpStatus, body } = await callCallable(HISTORY_URL, {}, idToken);
  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("organizationId is always server-derived — a client-sent override is silently ignored, and cannot be used to read another org's history", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  await seedLedgerEntry({ customerId: uid, organizationId: "org-evil" });
  await seedLedgerEntry({ customerId: uid, organizationId: ORG });

  const { httpStatus, body } = await callCallable(HISTORY_URL, { organizationId: "org-evil" }, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.rows.length, 1, "only the canonical org's entry is ever returned");
});

test("a customer cannot request another uid's history — the callable never reads request.data.customerId/uid", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  const { uid: victimUid } = await createRealPhoneUser();
  await seedTenantMembership(victimUid);
  await seedLedgerEntry({ customerId: victimUid });

  const { httpStatus, body } = await callCallable(HISTORY_URL, { uid: victimUid, customerId: victimUid }, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.rows.length, 0, "the caller's own (empty) history is returned, never another customer's");
});

// =========================================================================
// B. Own-history scoping, ordering, sanitization
// =========================================================================

test("only the caller's own history is returned, newest first", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  const { uid: otherUid } = await createRealPhoneUser();
  await seedTenantMembership(otherUid);

  const now = admin.firestore.Timestamp.now();
  const older = admin.firestore.Timestamp.fromMillis(now.toMillis() - 60_000);
  const oldest = admin.firestore.Timestamp.fromMillis(now.toMillis() - 120_000);
  await seedLedgerEntry({ customerId: uid, createdAt: oldest, entitlementDeltaBoncuk: 1, spendableDeltaBoncuk: 1 });
  await seedLedgerEntry({ customerId: uid, createdAt: older, entitlementDeltaBoncuk: 2, spendableDeltaBoncuk: 2 });
  await seedLedgerEntry({ customerId: uid, createdAt: now, entitlementDeltaBoncuk: 3, spendableDeltaBoncuk: 3 });
  await seedLedgerEntry({ customerId: otherUid, createdAt: now, entitlementDeltaBoncuk: 99, spendableDeltaBoncuk: 99 });

  const { httpStatus, body } = await callCallable(HISTORY_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  const rows = body.result!.rows;
  assert.strictEqual(rows.length, 3);
  assert.deepStrictEqual(rows.map((r) => r.displayBoncukDelta), [3, 2, 1], "newest first");
});

test("the sanitized response never leaks internal accounting fields", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  await seedLedgerEntry({ customerId: uid });

  const { body } = await callCallable(HISTORY_URL, {}, idToken);
  const row = body.result!.rows[0] as unknown as Record<string, unknown>;
  for (const forbiddenField of [
    "entitlementDeltaBoncuk", "spendableDeltaBoncuk", "debtDeltaBoncuk",
    "organizationId", "customerId", "sourceId", "idempotencyKey", "reversalOf",
    "amountBasisMinorUnits", "orderEligibleNetSpendBeforeMinorUnits",
    "orderEligibleNetSpendAfterMinorUnits", "orderEntitlementBeforeBoncuk",
    "orderEntitlementAfterBoncuk", "remainderBeforeMinorUnits", "remainderAfterMinorUnits",
    "earningRateMinorUnitsPerBoncuk", "debtBeforeBoncuk", "debtAfterBoncuk",
    "redemptionRateMinorUnitsPerBoncuk", "metadata",
  ]) {
    assert.strictEqual(forbiddenField in row, false, `row must not contain internal field "${forbiddenField}"`);
  }
  assert.deepStrictEqual(
    Object.keys(row).sort(),
    ["debtAppliedBoncuk", "displayBoncukDelta", "eventId", "occurredAt", "orderId", "type"].sort(),
  );
});

test("orderEarn with no debt: displayBoncukDelta equals the gross earn, debtAppliedBoncuk is 0", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  await seedLedgerEntry({ customerId: uid, entitlementDeltaBoncuk: 10, spendableDeltaBoncuk: 10, debtDeltaBoncuk: 0 });

  const { body } = await callCallable(HISTORY_URL, {}, idToken);
  const row = body.result!.rows[0];
  assert.strictEqual(row.type, "orderEarn");
  assert.strictEqual(row.displayBoncukDelta, 10);
  assert.strictEqual(row.debtAppliedBoncuk, 0);
});

test("orderEarn while debt exists: displayBoncukDelta is the gross earn, debtAppliedBoncuk reflects what was redirected to debt", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  // Case 1 of the locked P2B spec: gross 5, all 5 pays debt, spendable +0.
  await seedLedgerEntry({ customerId: uid, entitlementDeltaBoncuk: 5, spendableDeltaBoncuk: 0, debtDeltaBoncuk: -5 });

  const { body } = await callCallable(HISTORY_URL, {}, idToken);
  const row = body.result!.rows[0];
  assert.strictEqual(row.displayBoncukDelta, 5, "the customer still sees they earned 5, not 0");
  assert.strictEqual(row.debtAppliedBoncuk, 5);
});

test("orderId is passed through for order-linked entries, null otherwise", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  await seedLedgerEntry({ customerId: uid, orderId: "order-xyz" });

  const { body } = await callCallable(HISTORY_URL, {}, idToken);
  assert.strictEqual(body.result!.rows[0].orderId, "order-xyz");
});

// =========================================================================
// C. Pagination — bounded, deterministic
// =========================================================================

test("page size is bounded — a requested pageSize above the max is clamped, never returns more than MAX_PAGE_SIZE", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  for (let i = 0; i < 35; i += 1) {
    // eslint-disable-next-line no-await-in-loop
    await seedLedgerEntry({ customerId: uid });
  }

  const { body } = await callCallable(HISTORY_URL, { pageSize: 9999 }, idToken);
  assert.ok(body.result!.rows.length <= 30, "must never exceed MAX_PAGE_SIZE regardless of what the client requests");
});

test("pagination is deterministic — walking every page via nextCursor visits every entry exactly once, newest first, no gaps or duplicates", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  const now = admin.firestore.Timestamp.now();
  const total = 7;
  for (let i = 0; i < total; i += 1) {
    // eslint-disable-next-line no-await-in-loop
    await seedLedgerEntry({
      customerId: uid,
      createdAt: admin.firestore.Timestamp.fromMillis(now.toMillis() + i * 1000),
      entitlementDeltaBoncuk: i,
      spendableDeltaBoncuk: i,
    });
  }

  const seen: number[] = [];
  let cursor: string | null | undefined;
  let guard = 0;
  do {
    const { body } = await callCallable(HISTORY_URL, { pageSize: 3, cursor }, idToken);
    for (const row of body.result!.rows) seen.push(row.displayBoncukDelta);
    cursor = body.result!.nextCursor;
    guard += 1;
  } while (cursor && guard < 10);

  assert.deepStrictEqual(seen, [6, 5, 4, 3, 2, 1, 0], "every entry visited exactly once, newest first, across pages");
});

test("an invalid cursor is rejected, not silently ignored", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  const { httpStatus, body } = await callCallable(HISTORY_URL, { cursor: "not-a-timestamp" }, idToken);
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("no history yet returns an empty page, not an error", async () => {
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(uid);
  const { httpStatus, body } = await callCallable(HISTORY_URL, {}, idToken);
  assert.strictEqual(httpStatus, 200);
  assert.deepStrictEqual(body.result, { rows: [], nextCursor: null });
});

// =========================================================================
// D. Pure mapping function — direct unit tests
// =========================================================================

test("mapLedgerEntryToCustomerHistoryRow: redemption-direction entries use spendableDeltaBoncuk, never entitlementDeltaBoncuk", () => {
  const row = mapLedgerEntryToCustomerHistoryRow("entry-1", {
    entryType: "boncukRedemption",
    entitlementDeltaBoncuk: 0,
    spendableDeltaBoncuk: -20,
    createdAt: { toDate: () => new Date("2026-08-23T10:00:00.000Z") },
    orderId: null,
  });
  assert.strictEqual(row?.displayBoncukDelta, -20);
  assert.strictEqual(row?.debtAppliedBoncuk, 0);
});

test("mapLedgerEntryToCustomerHistoryRow: an unrecognized entryType is skipped (returns null), never fabricated", () => {
  const row = mapLedgerEntryToCustomerHistoryRow("entry-2", {
    entryType: "somethingUnknown",
    createdAt: { toDate: () => new Date() },
  });
  assert.strictEqual(row, null);
});

test("mapLedgerEntryToCustomerHistoryRow: a missing createdAt is skipped, never defaults to now", () => {
  const row = mapLedgerEntryToCustomerHistoryRow("entry-3", {
    entryType: "orderEarn",
    entitlementDeltaBoncuk: 1,
    spendableDeltaBoncuk: 1,
  });
  assert.strictEqual(row, null);
});
