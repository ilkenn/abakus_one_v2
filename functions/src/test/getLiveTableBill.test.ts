import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Adım 5 (2026-11-07) — emulator-backed tests for `getLiveTableBill`
 * (ADR-058's deferred "Canlı Adisyon" item). Fixtures (guest session,
 * orders, check, adjustment) are seeded directly into Firestore rather than
 * routed through `openTableGuestSession`/`submitDineInOrder` — this file
 * tests `getLiveTableBill`'s own authorization/aggregation logic in
 * isolation, same reasoning `checkFinancialAdjustments.test.ts`'s own
 * `seedTenant`/`seedMenuProduct` direct-seed helpers already use.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const GET_LIVE_TABLE_BILL_URL = fn("getLiveTableBill");

let app: admin.app.App;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID }); });
after(async () => { await app.delete(); });
const db = () => admin.firestore();

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as { result?: Record<string, unknown>; error?: { status?: string; message?: string } };
  return { httpStatus: response.status, body };
}

async function signUpAnonymously(): Promise<{ idToken: string; uid: string }> {
  const response = await fetch(`${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`, {
    method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }),
  });
  const body = (await response.json()) as { idToken: string; localId: string };
  return { idToken: body.idToken, uid: body.localId };
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
let idCounter = 0;
function nextId(prefix: string): string { idCounter += 1; return `${prefix}-${TEST_RUN_ID}-${idCounter}`; }

async function seedGuestSession(params: {
  guestAuthUid: string;
  tableSessionId: string;
  status?: string;
  expiresAt?: Date;
}): Promise<string> {
  const sessionRef = db().collection("tableGuestSessions").doc();
  await sessionRef.set({
    organizationId: nextId("org"),
    restaurantId: nextId("restaurant"),
    branchId: nextId("branch"),
    tableId: nextId("table"),
    tableSessionId: params.tableSessionId,
    guestAuthUid: params.guestAuthUid,
    status: params.status ?? "active",
    createdAt: admin.firestore.Timestamp.now(),
    expiresAt: admin.firestore.Timestamp.fromDate(
      params.expiresAt ?? new Date(Date.now() + 2 * 60 * 60 * 1000),
    ),
    lastActivityAt: admin.firestore.Timestamp.now(),
    qrTokenId: null,
  });
  return sessionRef.id;
}

async function seedAcceptedOrder(params: {
  tableSessionId: string;
  lines: Array<{
    productName: string;
    quantity: number;
    unitPriceMinorUnits: number;
    status?: string;
    modifiers?: Array<{ unitExtraPriceMinorUnits: number; quantity: number }>;
  }>;
}): Promise<void> {
  await db().collection("orders").doc(nextId("order")).set({
    dineInSessionGroupId: params.tableSessionId,
    lines: params.lines.map((l) => ({
      status: l.status ?? "accepted",
      productName: l.productName,
      quantity: l.quantity,
      unitPrice: { minorUnits: l.unitPriceMinorUnits, currencyCode: "TRY" },
      modifiers: (l.modifiers ?? []).map((m) => ({
        unitExtraPrice: { minorUnits: m.unitExtraPriceMinorUnits, currencyCode: "TRY" },
        quantity: m.quantity,
      })),
    })),
  });
}

async function seedCheck(params: { tableSessionId: string; status?: string }): Promise<string> {
  const checkRef = db().collection("checks").doc();
  await checkRef.set({
    organizationId: nextId("org"),
    branchId: nextId("branch"),
    tableSessionId: params.tableSessionId,
    status: params.status ?? "open",
    paymentActivityStarted: false,
    computedTotalMinorUnits: 0,
    currencyCode: "TRY",
    openedAt: admin.firestore.Timestamp.now(),
    readyForPaymentAt: null,
    cancelledAt: null,
    createdByStaffUid: "staff-1",
    version: 1,
  });
  return checkRef.id;
}

async function seedActiveAdjustment(checkId: string, appliedAmountMinorUnits: number): Promise<void> {
  await db().collection("checkFinancialAdjustments").doc().set({
    checkId,
    organizationId: nextId("org"),
    branchId: nextId("branch"),
    status: "active",
    appliedAmountMinorUnits,
  });
}

test("getLiveTableBill: sums accepted lines, subtracts active discounts, excludes non-accepted lines", async () => {
  const guest = await signUpAnonymously();
  const tableSessionId = nextId("tsess");
  const guestSessionId = await seedGuestSession({ guestAuthUid: guest.uid, tableSessionId });
  await seedAcceptedOrder({
    tableSessionId,
    lines: [
      { productName: "Klasik Bowl", quantity: 2, unitPriceMinorUnits: 15000 },
      { productName: "Ayran", quantity: 1, unitPriceMinorUnits: 3000, status: "pendingApproval" },
    ],
  });
  const checkId = await seedCheck({ tableSessionId });
  await seedActiveAdjustment(checkId, 5000);

  const { httpStatus, body } = await callCallable(
    GET_LIVE_TABLE_BILL_URL,
    { tableSessionId: guestSessionId },
    guest.idToken,
  );

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const result = body.result!;
  assert.strictEqual(result.subtotalMinorUnits, 30000, "only the accepted line counts (2x15000), pendingApproval excluded");
  assert.strictEqual(result.appliedDiscountsMinorUnits, 5000);
  assert.strictEqual(result.runningTotalMinorUnits, 25000);
  assert.strictEqual((result.lines as unknown[]).length, 1);
});

// 2026-11-10 — paid modifiers were left out of the guest's bill while the
// POS check charged them (same formula as computeLineValueMinorUnits).
test("getLiveTableBill: paid modifiers are part of the line price and the subtotal", async () => {
  const guest = await signUpAnonymously();
  const tableSessionId = nextId("tsess");
  const guestSessionId = await seedGuestSession({ guestAuthUid: guest.uid, tableSessionId });
  await seedAcceptedOrder({
    tableSessionId,
    lines: [
      {
        productName: "Acı Soslu Tavuk Bowl",
        quantity: 2,
        unitPriceMinorUnits: 52000,
        modifiers: [
          { unitExtraPriceMinorUnits: 15000, quantity: 1 },
          { unitExtraPriceMinorUnits: 2000, quantity: 2 },
        ],
      },
    ],
  });

  const { httpStatus, body } = await callCallable(
    GET_LIVE_TABLE_BILL_URL,
    { tableSessionId: guestSessionId },
    guest.idToken,
  );

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const result = body.result!;
  // (520 + 150 + 2 x 20) x 2 = 1420 TL.
  assert.strictEqual(result.subtotalMinorUnits, 142000);
  const line = (result.lines as Array<{ unitPriceMinorUnits: number }>)[0];
  assert.strictEqual(line.unitPriceMinorUnits, 71000, "per unit, modifiers included");
});

test("getLiveTableBill: a different guest's uid is rejected, never shown another table's bill", async () => {
  const owner = await signUpAnonymously();
  const stranger = await signUpAnonymously();
  const tableSessionId = nextId("tsess");
  const guestSessionId = await seedGuestSession({ guestAuthUid: owner.uid, tableSessionId });
  await seedAcceptedOrder({
    tableSessionId,
    lines: [{ productName: "Klasik Bowl", quantity: 1, unitPriceMinorUnits: 15000 }],
  });

  const { httpStatus, body } = await callCallable(
    GET_LIVE_TABLE_BILL_URL,
    { tableSessionId: guestSessionId },
    stranger.idToken,
  );

  assert.strictEqual(httpStatus, 400, JSON.stringify(body));
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("getLiveTableBill: a closed/expired guest session is rejected", async () => {
  const guest = await signUpAnonymously();
  const tableSessionId = nextId("tsess");
  const guestSessionId = await seedGuestSession({
    guestAuthUid: guest.uid,
    tableSessionId,
    status: "closed",
  });

  const { httpStatus, body } = await callCallable(
    GET_LIVE_TABLE_BILL_URL,
    { tableSessionId: guestSessionId },
    guest.idToken,
  );

  assert.strictEqual(httpStatus, 400, JSON.stringify(body));
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("getLiveTableBill: unauthenticated call is rejected", async () => {
  const { httpStatus, body } = await callCallable(GET_LIVE_TABLE_BILL_URL, { tableSessionId: "whatever" });

  assert.strictEqual(httpStatus, 401, JSON.stringify(body));
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});
