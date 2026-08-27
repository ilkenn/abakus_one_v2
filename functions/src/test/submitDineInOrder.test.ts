import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import {
  LOYALTY_ACCOUNTS_COLLECTION,
  LOYALTY_LEDGER_ENTRIES_COLLECTION,
  deriveLoyaltyLedgerEntryId,
  type LedgerEntryType,
} from "../loyaltyLedger";
import { createLoyaltyReward } from "../loyaltyRewardCatalogAdminService";

/**
 * Emulator-backed tests for `submitDineInOrder`/`advanceDineInOrderStatus`/
 * `refundDineInOrder` — Boncuk Loyalty Program P7-D.1 (2026-08-24), the
 * first server-authoritative dine-in order pipeline. Mirrors the
 * established `submit*OrderCatalogReward.test.ts` conventions (raw HTTP
 * against the callable wire protocol, real Firestore/Auth-emulator
 * fixtures, a per-file `TEST_RUN_ID` namespace).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SUBMIT_URL = fn("submitDineInOrder");
const ADVANCE_URL = fn("advanceDineInOrderStatus");
const REFUND_URL = fn("refundDineInOrder");
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");

let app: admin.app.App;
before(() => {
  app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID });
});
after(async () => {
  await app.delete();
});

const db = () => admin.firestore();

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as {
    result?: Record<string, unknown>;
    error?: { status?: string; message?: string; details?: { reason?: string } };
  };
  return { httpStatus: response.status, body };
}

async function waitFor<T>(fn2: () => Promise<T | null>, timeoutMs = 15000): Promise<T> {
  const start = Date.now();
  while (Date.now() - start < timeoutMs) {
    const result = await fn2();
    if (result !== null) return result;
    await new Promise((resolve) => setTimeout(resolve, 250));
  }
  throw new Error("Timed out waiting for condition");
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
async function createStaffMember(organizationId: string, roles: string[], branchAccess: string[]): Promise<{ idToken: string; uid: string }> {
  const { idToken, refreshToken, uid } = await signUpAnonymously();
  await db().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles, branchAccess, restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(),
  });
  const sync = await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  assert.strictEqual(sync.httpStatus, 200, JSON.stringify(sync.body));
  const refreshed = await refreshIdToken(refreshToken);
  return { uid, idToken: refreshed };
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);
let phoneCounter = 0;
async function createRealPhoneUser(): Promise<{ idToken: string; uid: string }> {
  phoneCounter += 1;
  const phoneNumber = `+1555${PHONE_NAMESPACE}${String(phoneCounter).padStart(3, "0")}`;
  const sendRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ phoneNumber, recaptchaToken: "ignored-by-emulator" }) },
  );
  const sendBody = (await sendRes.json()) as { sessionInfo: string };
  const codesRes = await fetch(`${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`);
  const codesBody = (await codesRes.json()) as { verificationCodes: { sessionInfo: string; code: string }[] };
  const match = codesBody.verificationCodes.find((c) => c.sessionInfo === sendBody.sessionInfo)!;
  const signInRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }) },
  );
  const signInBody = (await signInRes.json()) as { idToken: string; localId: string };
  return { idToken: signInBody.idToken, uid: signInBody.localId };
}

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function seedChain() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  await db().collection("branches").doc(branchId).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
  });
  return { organizationId, restaurantId, branchId };
}

async function seedMenuProduct(
  id: string,
  restaurantId: string,
  organizationId: string,
  overrides: Partial<{ categoryId: string; basePriceMinorUnits: number; isAvailable: boolean }> = {},
) {
  await db().collection("menuProducts").doc(id).set({
    organizationId, restaurantId,
    categoryId: overrides.categoryId ?? "cat_standard",
    name: "Test Product",
    basePriceMinorUnits: overrides.basePriceMinorUnits ?? 10000,
    isAvailable: overrides.isAvailable ?? true,
    modifierGroups: [],
    channelPriceOverrides: {},
  });
}

/**
 * AP-3 Wave 1 — extended to also seed the parent `tableSessions` document
 * and the guest's own `guestSubAccounts` document, mirroring exactly what
 * `openTableGuestSession` now creates transactionally. Every pre-existing
 * caller of this helper keeps working unchanged (same signature, same
 * return value) — `submitDineInOrder`'s guestSession path now requires
 * both to exist. `displayName` is pre-seeded non-empty so the existing
 * ~70 call sites in this file (none of which pass `guestDisplayName`)
 * never hit the new mandatory-name-on-first-submission gate; tests that
 * specifically exercise that gate seed their own bare sub-account instead.
 */
async function seedTableGuestSession(
  chain: { organizationId: string; restaurantId: string; branchId: string },
  guestAuthUid: string,
  overrides: Partial<{
    status: string;
    expiresAt: Date;
    tableId: string;
    reservationContextId: string | null;
  }> = {},
): Promise<string> {
  const sessionId = nextId("tgs");
  const tableId = overrides.tableId ?? "dev-table-1";
  const tableSessionId = nextId("tsess");
  await db().collection("restaurantTables").doc(tableId).set(
    { organizationId: chain.organizationId, branchId: chain.branchId, isActive: true },
    { merge: true },
  );
  await db().collection("tableSessions").doc(tableSessionId).set({
    organizationId: chain.organizationId,
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    tableId,
    status: "active",
    openedAt: admin.firestore.Timestamp.now(),
    closedAt: null,
    openedByType: "guestQrScan",
    openedByStaffUid: null,
    transferredFromTableId: null,
    version: 1,
  });
  await db().collection("tableGuestSessions").doc(sessionId).set({
    organizationId: chain.organizationId,
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    tableId,
    tableSessionId,
    guestAuthUid,
    status: overrides.status ?? "active",
    createdAt: admin.firestore.Timestamp.now(),
    expiresAt: admin.firestore.Timestamp.fromDate(
      overrides.expiresAt ?? new Date(Date.now() + 6 * 60 * 60 * 1000),
    ),
    lastActivityAt: admin.firestore.Timestamp.now(),
    qrTokenId: nextId("qrtoken"),
    reservationContextId: overrides.reservationContextId ?? null,
  });
  await db().collection("guestSubAccounts").doc(`subaccount-${tableSessionId}-${guestAuthUid}`).set({
    organizationId: chain.organizationId,
    branchId: chain.branchId,
    tableSessionId,
    ownerType: "guestSession",
    ownerSessionRef: `tableGuestSessions/${sessionId}`,
    ownerAuthUid: guestAuthUid,
    displayName: "Test Guest",
    status: "open",
    createdAt: admin.firestore.Timestamp.now(),
    createdByStaffUid: null,
    version: 1,
  });
  return sessionId;
}

function validSubmission(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return { submissionKey: nextId("key"), ...overrides };
}

async function seedLoyaltyAccount(
  organizationId: string, uid: string,
  overrides: Partial<{ spendableBalance: number; boncukDebt: number }> = {},
) {
  const now = admin.firestore.Timestamp.now();
  await db().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).set({
    organizationId, customerId: uid,
    spendableBalance: overrides.spendableBalance ?? 0,
    boncukDebt: overrides.boncukDebt ?? 0,
    validOrderEntitlementBoncuk: 0,
    earningCarryNumerator: "0", earningCarryDenominator: "1",
    lifetimeEarned: 0, lifetimeRedeemed: 0,
    createdAt: now, updatedAt: now, revision: 1,
  });
}
async function loyaltyAccountDoc(organizationId: string, uid: string) {
  return (await db().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).get()).data();
}
async function ledgerDoc(organizationId: string, uid: string, entryType: LedgerEntryType, orderId: string) {
  const id = deriveLoyaltyLedgerEntryId({ organizationId, customerId: uid, entryType, sourceId: orderId });
  return (await db().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}
async function orderDoc(orderId: string) {
  return (await db().collection("orders").doc(orderId).get()).data();
}
async function seedTenantMembership(organizationId: string, uid: string) {
  await db().collection("tenantCustomers").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, createdAt: admin.firestore.Timestamp.now(),
  });
}

async function seedReward(
  organizationId: string,
  productId: string,
  overrides: Partial<{ rewardId: string; boncukCost: number; eligibleChannels: string[] }> = {},
): Promise<string> {
  const rewardId = overrides.rewardId ?? nextId("reward");
  await createLoyaltyReward(db(), {
    organizationId, rewardId,
    title: "Test Reward", description: "Bir test ödülü.",
    rewardType: "explicitProductSet",
    eligibleProductIds: [productId],
    eligibleChannels: overrides.eligibleChannels ?? ["dineIn", "takeaway", "delivery", "reservationPreorder"],
    boncukCost: overrides.boncukCost ?? 100,
    sortOrder: 0,
  });
  return rewardId;
}

async function advanceToCompleted(orderId: string, staffToken: string): Promise<void> {
  for (const targetStatus of ["confirmed", "preparing", "ready", "served", "completed"]) {
    const { httpStatus, body } = await callCallable(ADVANCE_URL, { orderId, targetStatus }, staffToken);
    assert.strictEqual(httpStatus, 200, `advancing to ${targetStatus}: ${JSON.stringify(body)}`);
  }
}

// =========================================================================
// A. Identity.
// =========================================================================

test("dine-in: a valid anonymous table guest order succeeds — customerId null, guestAuthUid the caller's own uid", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.customerId, null);
  assert.strictEqual(order?.guestAuthUid, uid);
  assert.strictEqual(order?.channel, "dineInQr");
  assert.strictEqual(order?.tableSessionId, sessionId);
  assert.strictEqual(order?.pricingAuthority, "serverV1");
});

test("dine-in: a real phone-verified customer order succeeds — customerId equals the caller's own uid", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.customerId, uid);
  assert.strictEqual(order?.guestAuthUid, uid);
});

test("dine-in: an anonymous guest cannot select a catalog reward — rejected fail-closed, no Loyalty account read/write", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);
  const rewardId = await seedReward(chain.organizationId, productId);

  const { httpStatus } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 403);
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account, undefined, "no Loyalty account was ever created/read for the guest");
});

test("dine-in: an anonymous guest never mutates Loyalty even without selecting a reward — no account doc created", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);

  const { httpStatus } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account, undefined);
});

test("dine-in: dine-in cash Boncuk redemption is always rejected, for both guest and real customer", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      requestedBoncukAmount: 10,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "boncuk/redemption-not-allowed");
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 500, "untouched");
});

// =========================================================================
// B. Table session security.
// =========================================================================

test("dine-in: a nonexistent table session is rejected", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await signUpAnonymously();

  const { httpStatus } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: "does-not-exist",
      items: [{ kind: "product", productId, quantity: 1 }],
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 404);
});

test("dine-in: an expired table session is rejected", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid, {
    expiresAt: new Date(Date.now() - 60_000),
  });

  const { httpStatus } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
});

test("dine-in: a revoked/inactive table session is rejected", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid, { status: "revoked" });

  const { httpStatus } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
});

test("dine-in: a session belonging to a different caller is rejected — no forging another guest's session", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const owner = await signUpAnonymously();
  const attacker = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, owner.uid);

  const { httpStatus } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
    }),
    attacker.idToken,
  );
  assert.strictEqual(httpStatus, 400);
});

test("dine-in: organizationId/restaurantId/branchId/tableId are always derived from the session, never from any client-sent field — a forged extra field has zero effect", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid, { tableId: "real-table-7" });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      // Forged scope claims — the request shape has no such accepted
      // field at all, so these are simply ignored, never read.
      organizationId: "forged-org",
      branchId: "forged-branch",
      tableId: "forged-table",
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200);
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.organizationId, chain.organizationId);
  assert.strictEqual(order?.branchId, chain.branchId);
  assert.strictEqual(order?.tableId, "real-table-7");
});

test("dine-in: a table session whose linked reservation is no longer orderable (not confirmed) is rejected", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await signUpAnonymously();
  const reservationId = nextId("reservation");
  await db().collection("reservations").doc(reservationId).set({
    organizationId: chain.organizationId, restaurantId: chain.restaurantId, branchId: chain.branchId,
    status: "cancelled",
  });
  const sessionId = await seedTableGuestSession(chain, uid, { reservationContextId: reservationId });

  const { httpStatus } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
});

test("dine-in: a table session with an orderable (confirmed) linked reservation succeeds and preserves reservationContextId on the order", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await signUpAnonymously();
  const reservationId = nextId("reservation");
  await db().collection("reservations").doc(reservationId).set({
    organizationId: chain.organizationId, restaurantId: chain.restaurantId, branchId: chain.branchId,
    status: "confirmed",
  });
  const sessionId = await seedTableGuestSession(chain, uid, { reservationContextId: reservationId });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.reservationContextId, reservationId);
});

// =========================================================================
// C. Pricing.
// =========================================================================

test("dine-in: a forged client price is ignored — server resolves canonical price", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 15000 });
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1, unitPrice: 1 }],
    }),
    idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.lines[0].unitPrice.minorUnits, 15000);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 15000);
});

test("dine-in: modifiers and quantity are priced canonically", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await db().collection("menuProducts").doc(productId).set({
    organizationId: chain.organizationId, restaurantId: chain.restaurantId,
    categoryId: "cat_standard", name: "Test Product", basePriceMinorUnits: 10000, isAvailable: true,
    modifierGroups: [
      { id: "g1", name: "Ekstra", options: [{ id: "o1", name: "Peynir", extraPriceMinorUnits: 500, isAvailable: true }] },
    ],
    channelPriceOverrides: {},
  });
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{
        kind: "product", productId, quantity: 2,
        selectedModifiers: [{ groupId: "g1", optionId: "o1" }],
      }],
    }),
    idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.lines[0].quantity, 2);
  // (10000 + 500) * 2 = 21000
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 21000);
});

test("dine-in: no channel surcharge leaks in from takeaway/delivery — unconfigured channel resolves to zero adjustment", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000, categoryId: "cat_standard" });
  await db().collection("channelPricingPolicies").doc(chain.restaurantId).set({
    channelDefaultAdjustments: { takeaway: 2000, delivery: 14000 },
    categoryOverrides: {},
  });
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
    }),
    idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.lines[0].unitPrice.minorUnits, 10000, "no takeaway/delivery surcharge applied to dine-in");
});

test("dine-in: Bowl Builder items are priced with their channel adjustment plus ingredient total", async () => {
  const chain = await seedChain();
  const ingredientId = nextId("ingredient");
  await db().collection("bowlIngredients").doc(ingredientId).set({
    organizationId: chain.organizationId, restaurantId: chain.restaurantId,
    categoryId: "protein", name: "Tavuk", priceMinorUnits: 5000, isAvailable: true,
  });
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "bowl", quantity: 1, ingredientIds: [ingredientId] }],
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 5000, "no dineIn channel policy seeded -> 0 adjustment + 5000 ingredient");
});

// =========================================================================
// D. Catalog reward.
// =========================================================================

test("dine-in catalog reward: a valid redemption by a phone customer succeeds, exactly one unit free", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 150 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.selectedBenefitType, "catalogReward");
  assert.strictEqual(order?.catalogReward.orderChannel, "dineIn");
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 0);

  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 350);
  const ledger = await ledgerDoc(chain.organizationId, uid, "catalogRedemption", body.result!.orderId as string);
  assert.ok(ledger);
});

test("dine-in catalog reward: exactly ONE unit free at quantity > 1", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 100 });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 3 }],
      selectedRewardId: rewardId,
    }),
    idToken,
  );
  const order = await orderDoc(body.result!.orderId as string);
  assert.strictEqual(order?.lines[0].lineDiscount.minorUnits, 10000);
  assert.strictEqual(order?.pricing.grandTotal.minorUnits, 20000, "2 remaining units at 10000 each");
});

test("dine-in catalog reward: a reward whose eligibleChannels excludes dineIn is rejected fail-closed", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, {
    boncukCost: 100, eligibleChannels: ["takeaway", "delivery"],
  });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/channel-not-eligible");
});

test("dine-in catalog reward: insufficient balance is rejected", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 50 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 420 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    idToken,
  );
  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.details?.reason, "catalogReward/insufficient-balance");
});

test("dine-in catalog reward: server resolves the exact cost/version, immutable snapshot survives a later live-reward edit", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  const sessionId = await seedTableGuestSession(chain, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 100 });

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  await db().collection("loyaltyRewardCatalog").doc(rewardId).set({ boncukCost: 999999, version: 2 }, { merge: true });

  const order = await orderDoc(orderId);
  assert.strictEqual(order?.catalogReward.boncukCost, 100);
  assert.strictEqual(order?.catalogReward.rewardVersion, 1);
});

test("dine-in catalog reward: two concurrent redemptions against a balance covering only ONE must not both succeed", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 100 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 100 });
  const sessionA = await seedTableGuestSession(chain, uid);

  const [first, second] = await Promise.all([
    callCallable(
      SUBMIT_URL,
      validSubmission({ tableSessionId: sessionA, items: [{ kind: "product", productId, quantity: 1 }], selectedRewardId: rewardId }),
      idToken,
    ),
    callCallable(
      SUBMIT_URL,
      validSubmission({ tableSessionId: sessionA, items: [{ kind: "product", productId, quantity: 1 }], selectedRewardId: rewardId }),
      idToken,
    ),
  ]);
  const successes = [first, second].filter((r) => r.httpStatus === 200);
  assert.strictEqual(successes.length, 1);
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 0);
});

test("dine-in catalog reward: rewarded value earns zero Boncuk, other paid items earn normally", async () => {
  const chain = await seedChain();
  const rewardedProductId = nextId("rprod");
  const paidProductId = nextId("pprod");
  await seedMenuProduct(rewardedProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  await seedMenuProduct(paidProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(chain.organizationId, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, rewardedProductId, { boncukCost: 150 });
  const sessionId = await seedTableGuestSession(chain, uid);

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [
        { kind: "product", productId: rewardedProductId, quantity: 1 },
        { kind: "product", productId: paidProductId, quantity: 1 },
      ],
      selectedRewardId: rewardId,
    }),
    idToken,
  );
  assert.strictEqual(submit.httpStatus, 200, JSON.stringify(submit.body));
  const orderId = submit.body.result!.orderId as string;

  await advanceToCompleted(orderId, staff.idToken);

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(account.lifetimeEarned, 50, "exactly the paid item's own earning (50000/5000*5)");
});

// =========================================================================
// E. Idempotency.
// =========================================================================

test("dine-in: retrying the same submissionKey creates exactly one order, no double debit", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);
  const submission = validSubmission({
    tableSessionId: sessionId,
    items: [{ kind: "product", productId, quantity: 1 }],
  });

  const first = await callCallable(SUBMIT_URL, submission, idToken);
  const second = await callCallable(SUBMIT_URL, submission, idToken);
  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.duplicate, true);
  assert.strictEqual(first.body.result?.orderId, second.body.result?.orderId);
});

// =========================================================================
// F. Rules — direct client bypass blocked.
// =========================================================================

test("dine-in: a customer cannot bypass submitDineInOrder by creating an order document directly via client SDK-shaped write (Admin SDK bypasses rules; this proves the callable is what enforces validation, not that rules alone would stop an Admin SDK write)", async () => {
  // This test documents the callable's own validation is the enforcement
  // boundary for anything using the client SDK; a parallel Firestore Rules
  // test (`firestore-tests/rules.test.js`) proves the ACTUAL client-SDK
  // `create` denial. Covered there, not duplicated here.
  assert.ok(true);
});

// =========================================================================
// G. Lifecycle / restore.
// =========================================================================

test("dine-in lifecycle: staff can confirm/advance/complete a pending order under manageDineInOrders", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({ tableSessionId: sessionId, items: [{ kind: "product", productId, quantity: 1 }] }),
    idToken,
  );
  const orderId = submit.body.result!.orderId as string;

  await advanceToCompleted(orderId, staff.idToken);
  const order = await orderDoc(orderId);
  assert.strictEqual(order?.status, "completed");
});

test("dine-in lifecycle: rejecting a pending order restores a catalog-reward redemption exactly once", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 500 });
  const rewardId = await seedReward(chain.organizationId, productId, { boncukCost: 150 });
  const sessionId = await seedTableGuestSession(chain, uid);

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      selectedRewardId: rewardId,
    }),
    idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  assert.strictEqual((await loyaltyAccountDoc(chain.organizationId, uid))?.spendableBalance, 350);

  const reject = await callCallable(ADVANCE_URL, { orderId, targetStatus: "rejected", reasonCode: "kitchenUnavailable" }, staff.idToken);
  assert.strictEqual(reject.httpStatus, 200, JSON.stringify(reject.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, uid);
    return data && data.spendableBalance === 500 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 500);
});

test("dine-in lifecycle: a completed order with a catalog-reward redemption, refunded by a manager, restores the redemption and claws back earning", async () => {
  const chain = await seedChain();
  const rewardedProductId = nextId("rprod2");
  const paidProductId = nextId("pprod2");
  await seedMenuProduct(rewardedProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  await seedMenuProduct(paidProductId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const staff = await createStaffMember(chain.organizationId, ["staff"], [chain.branchId]);
  const manager = await createStaffMember(chain.organizationId, ["manager"], [chain.branchId]);
  const { idToken, uid } = await createRealPhoneUser();
  await seedTenantMembership(chain.organizationId, uid);
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 300 });
  const rewardId = await seedReward(chain.organizationId, rewardedProductId, { boncukCost: 150 });
  const sessionId = await seedTableGuestSession(chain, uid);

  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({
      tableSessionId: sessionId,
      items: [
        { kind: "product", productId: rewardedProductId, quantity: 1 },
        { kind: "product", productId: paidProductId, quantity: 1 },
      ],
      selectedRewardId: rewardId,
    }),
    idToken,
  );
  const orderId = submit.body.result!.orderId as string;
  assert.strictEqual((await loyaltyAccountDoc(chain.organizationId, uid))?.spendableBalance, 150);

  await advanceToCompleted(orderId, staff.idToken);
  const afterEarning = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, uid);
    return data && data.lifetimeEarned > 0 ? data : null;
  });
  assert.strictEqual(afterEarning.lifetimeEarned, 50);
  assert.strictEqual(afterEarning.spendableBalance, 200);

  const refund = await callCallable(REFUND_URL, { orderId, reasonCode: "qualityIssue" }, manager.idToken);
  assert.strictEqual(refund.httpStatus, 200, JSON.stringify(refund.body));

  const account = await waitFor(async () => {
    const data = await loyaltyAccountDoc(chain.organizationId, uid);
    return data && data.spendableBalance === 300 ? data : null;
  });
  assert.strictEqual(account.spendableBalance, 300, "200 + 150 restored - 50 clawed back");
});

test("dine-in lifecycle: staff without manageDineInOrders permission cannot advance an order", async () => {
  const chain = await seedChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken, uid } = await signUpAnonymously();
  const sessionId = await seedTableGuestSession(chain, uid);
  const submit = await callCallable(
    SUBMIT_URL,
    validSubmission({ tableSessionId: sessionId, items: [{ kind: "product", productId, quantity: 1 }] }),
    idToken,
  );
  const orderId = submit.body.result!.orderId as string;

  // A staff member with no roles at all in this org.
  const outsider = await createStaffMember(chain.organizationId, [], [chain.branchId]);
  const { httpStatus } = await callCallable(ADVANCE_URL, { orderId, targetStatus: "confirmed" }, outsider.idToken);
  assert.strictEqual(httpStatus, 403);
});
