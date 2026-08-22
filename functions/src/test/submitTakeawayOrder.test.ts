import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { LOYALTY_ACCOUNTS_COLLECTION, LOYALTY_LEDGER_ENTRIES_COLLECTION, deriveLoyaltyLedgerEntryId } from "../loyaltyLedger";

/**
 * Emulator-backed tests for `submitTakeawayOrder` — Faz D.3
 * (Server-Authoritative Pricing + Takeaway Order Creation), the most
 * security-critical function this app has. Follows every prior test
 * file's exact pattern: raw HTTP against the callable-functions wire
 * protocol, real Firestore fixtures seeded directly via the Admin SDK
 * (bypassing `provision*`/other callables — these are test fixtures
 * exercising `submitTakeawayOrder` itself, not those functions).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SUBMIT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/submitTakeawayOrder`;
const OPEN_SESSION_URL =
  `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/openTakeawayGuestSession`;

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

async function createAnonymousUser(): Promise<{ idToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ returnSecureToken: true }),
    },
  );
  const body = (await response.json()) as { idToken: string; localId: string };
  return { idToken: body.idToken, uid: body.localId };
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
  const codesRes = await fetch(
    `${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`,
  );
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

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

async function seedOrganization(id: string, overrides: Partial<{ isActive: boolean }> = {}) {
  await admin.firestore().collection("organizations").doc(id).set({
    name: "Test Org",
    isActive: true,
    ...overrides,
  });
}
async function seedRestaurant(
  id: string,
  organizationId: string,
  overrides: Partial<{ isActive: boolean }> = {},
) {
  await admin
    .firestore()
    .collection("restaurants")
    .doc(id)
    .set({ organizationId, name: "Test Restaurant", isActive: true, ...overrides });
}
async function seedBranch(
  id: string,
  restaurantId: string,
  organizationId: string,
  overrides: Partial<{
    status: string;
    emergencyStopped: boolean;
    supportedOrderChannelIds: string[];
  }> = {},
) {
  await admin
    .firestore()
    .collection("branches")
    .doc(id)
    .set({
      restaurantId,
      organizationId,
      name: "Merkez Şube",
      status: "active",
      emergencyStopped: false,
      supportedOrderChannelIds: ["takeaway"],
      ...overrides,
    });
}

/** A full, valid organization -> restaurant -> branch chain, ready for takeaway. */
async function seedValidChain() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  return { organizationId, restaurantId, branchId };
}

/** Boncuk Loyalty P4-B — a fully-shaped, well-formed loyalty account (the "normal existing account" baseline every redemption test starts from), keyed exactly like `getCustomerLoyaltySnapshot`'s own provisioning shape. */
async function seedLoyaltyAccount(
  organizationId: string,
  uid: string,
  overrides: Partial<{ spendableBalance: number; boncukDebt: number; lifetimeRedeemed: number; revision: number }> = {},
) {
  const now = admin.firestore.Timestamp.now();
  await admin
    .firestore()
    .collection(LOYALTY_ACCOUNTS_COLLECTION)
    .doc(`${organizationId}_${uid}`)
    .set({
      organizationId,
      customerId: uid,
      spendableBalance: overrides.spendableBalance ?? 0,
      boncukDebt: overrides.boncukDebt ?? 0,
      validOrderEntitlementBoncuk: 0,
      earningCarryNumerator: "0",
      earningCarryDenominator: "1",
      lifetimeEarned: 0,
      lifetimeRedeemed: overrides.lifetimeRedeemed ?? 0,
      createdAt: now,
      updatedAt: now,
      revision: overrides.revision ?? 1,
    });
}

async function loyaltyAccountDoc(organizationId: string, uid: string) {
  return (
    await admin.firestore().collection(LOYALTY_ACCOUNTS_COLLECTION).doc(`${organizationId}_${uid}`).get()
  ).data();
}

async function boncukRedemptionLedgerDoc(organizationId: string, uid: string, orderId: string) {
  const id = deriveLoyaltyLedgerEntryId({
    organizationId,
    customerId: uid,
    entryType: "boncukRedemption",
    sourceId: orderId,
  });
  return (await admin.firestore().collection(LOYALTY_LEDGER_ENTRIES_COLLECTION).doc(id).get()).data();
}

async function seedChannelPricingPolicy(
  restaurantId: string,
  policy: {
    channelDefaultAdjustments?: Record<string, number>;
    categoryOverrides?: Record<string, Record<string, number>>;
  },
) {
  await admin
    .firestore()
    .collection("channelPricingPolicies")
    .doc(restaurantId)
    .set({
      channelDefaultAdjustments: policy.channelDefaultAdjustments ?? {},
      categoryOverrides: policy.categoryOverrides ?? {},
    });
}

interface SeedProductOverrides {
  categoryId?: string;
  basePriceMinorUnits?: number;
  isAvailable?: boolean;
  modifierGroups?: unknown[];
  channelPriceOverrides?: Record<string, unknown>;
}

async function seedMenuProduct(
  id: string,
  restaurantId: string,
  organizationId: string,
  overrides: SeedProductOverrides = {},
) {
  await admin
    .firestore()
    .collection("menuProducts")
    .doc(id)
    .set({
      organizationId,
      restaurantId,
      categoryId: overrides.categoryId ?? "cat_bowl",
      name: "Test Product",
      basePriceMinorUnits: overrides.basePriceMinorUnits ?? 10000,
      isAvailable: overrides.isAvailable ?? true,
      modifierGroups: overrides.modifierGroups ?? [],
      channelPriceOverrides: overrides.channelPriceOverrides ?? {},
    });
}

async function seedBowlIngredient(
  id: string,
  restaurantId: string,
  organizationId: string,
  overrides: Partial<{ priceMinorUnits: number; isAvailable: boolean; categoryId: string }> = {},
) {
  await admin
    .firestore()
    .collection("bowlIngredients")
    .doc(id)
    .set({
      organizationId,
      restaurantId,
      categoryId: overrides.categoryId ?? "protein",
      name: "Test Ingredient",
      priceMinorUnits: overrides.priceMinorUnits ?? 5000,
      isAvailable: overrides.isAvailable ?? true,
    });
}

async function seedTakeawayQrCode(
  restaurantId: string,
  branchId: string,
  organizationId: string,
): Promise<string> {
  const token = nextId("token");
  await admin.firestore().collection("takeawayQrCodes").doc(nextId("qr")).set({
    opaqueToken: token,
    organizationId,
    restaurantId,
    branchId,
    status: "active",
  });
  return token;
}

/** A fully valid, active guest session for a fresh chain — the standard fixture every QR-guest happy-path test starts from. */
async function seedGuestSession(): Promise<{
  organizationId: string;
  restaurantId: string;
  branchId: string;
  sessionId: string;
  idToken: string;
  uid: string;
}> {
  const chain = await seedValidChain();
  const token = await seedTakeawayQrCode(chain.restaurantId, chain.branchId, chain.organizationId);
  const { idToken, uid } = await createAnonymousUser();
  const opened = await callCallable(OPEN_SESSION_URL, { token }, idToken);
  const sessionId = opened.body.result?.sessionId as string;
  return { ...chain, sessionId, idToken, uid };
}

function futurePickupIso(minutesFromNow: number): string {
  return new Date(Date.now() + minutesFromNow * 60 * 1000).toISOString();
}

const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz", contactPhone: "+905551112233" };

// =======================================================================
// A. QR guest scenarios
// =======================================================================

test("QR guest: a valid order succeeds — order created with server-derived scope, asap pickup, null customerId", async () => {
  const session = await seedGuestSession();
  const productId = nextId("product");
  await seedMenuProduct(productId, session.restaurantId, session.organizationId, {
    categoryId: "cat_bowl",
    basePriceMinorUnits: 43000,
  });
  await seedChannelPricingPolicy(session.restaurantId, { channelDefaultAdjustments: { takeaway: 2000 } });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      takeawaySessionId: session.sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    session.idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const orderId = body.result?.orderId as string;
  assert.ok(orderId);
  const order = (await admin.firestore().collection("orders").doc(orderId).get()).data()!;
  assert.strictEqual(order.channel, "takeaway");
  assert.strictEqual(order.customerId, null);
  assert.strictEqual(order.guestAuthUid, session.uid);
  assert.strictEqual(order.organizationId, session.organizationId);
  assert.strictEqual(order.restaurantId, session.restaurantId);
  assert.strictEqual(order.branchId, session.branchId);
  assert.strictEqual(order.pickupMode, "asap");
  assert.strictEqual(order.pickupTime, null);
  assert.strictEqual(order.status, "pendingConfirmation");
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 45000);
  // Boncuk Loyalty P2A security fix (2026-08-21) — the exact canonical
  // server pricing-authority marker, stamped by this callable itself.
  assert.strictEqual(order.pricingAuthority, "serverV1");
});

test("QR guest: pricingAuthority cannot originate from the request payload — the server always stamps its own canonical value regardless of what the client sends", async () => {
  const session = await seedGuestSession();
  const productId = nextId("product");
  await seedMenuProduct(productId, session.restaurantId, session.organizationId, {
    categoryId: "cat_bowl",
    basePriceMinorUnits: 43000,
  });
  await seedChannelPricingPolicy(session.restaurantId, { channelDefaultAdjustments: { takeaway: 2000 } });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      takeawaySessionId: session.sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
      // An attempted client override — must be silently ignored, never
      // read from request.data at all.
      pricingAuthority: "client-forged-value",
    },
    session.idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const orderId = body.result?.orderId as string;
  const order = (await admin.firestore().collection("orders").doc(orderId).get()).data()!;
  assert.strictEqual(order.pricingAuthority, "serverV1");
});

test("QR guest: an expired session is rejected — no order created", async () => {
  const chain = await seedValidChain();
  const token = await seedTakeawayQrCode(chain.restaurantId, chain.branchId, chain.organizationId);
  const { idToken, uid } = await createAnonymousUser();
  const opened = await callCallable(OPEN_SESSION_URL, { token }, idToken);
  const sessionId = opened.body.result?.sessionId as string;
  // Force the session into the past directly (bypassing the 30-minute
  // real TTL so this test doesn't need to wait).
  await admin
    .firestore()
    .collection("takeawayGuestSessions")
    .doc(sessionId)
    .update({ expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 60_000) });
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      takeawaySessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const orders = await admin.firestore().collection("orders").where("guestAuthUid", "==", uid).get();
  assert.strictEqual(orders.size, 0);
});

test("QR guest: a session belonging to a different uid is rejected — no order created", async () => {
  const session = await seedGuestSession();
  const attacker = await createAnonymousUser();
  const productId = nextId("product");
  await seedMenuProduct(productId, session.restaurantId, session.organizationId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      takeawaySessionId: session.sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    attacker.idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("QR guest: attempting a scheduled pickup (sending pickupMode/pickupTime/restaurantId/branchId) is rejected outright", async () => {
  const session = await seedGuestSession();
  const productId = nextId("product");
  await seedMenuProduct(productId, session.restaurantId, session.organizationId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      takeawaySessionId: session.sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      ...CONTACT,
    },
    session.idToken,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

// =======================================================================
// A.1 (Faz D.4.1) — entry-mode identity consistency. Root cause: dispatch
// used to key off `sign_in_provider` instead of "does this request
// reference a valid takeawayGuestSessions record" — so a real,
// phone-verified customer who scanned the physical kasadaki QR (Faz D.4's
// own Flutter flow never overwrites an existing session, by design) would
// have their guest checkout submission rejected with `invalid-argument`
// the moment they tried to submit, since the old dispatch treated any
// phone-auth caller sending `takeawaySessionId` as spoofing the
// authenticated path. Fixed: dispatch is now keyed on `takeawaySessionId`
// presence (entry mode) — see `docs/decisions.md` ADR-027 Faz D.4.1.
// =======================================================================

test("Faz D.4.1 (B): a real, phone-verified customer who scans the QR (has a valid guest session) submits a guest ASAP order successfully — entry mode, not auth provider, determines semantics", async () => {
  const chain = await seedValidChain();
  const token = await seedTakeawayQrCode(chain.restaurantId, chain.branchId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  const opened = await callCallable(OPEN_SESSION_URL, { token }, idToken);
  assert.strictEqual(opened.httpStatus, 200, "openTakeawayGuestSession must accept a real phone-verified caller too");
  const sessionId = opened.body.result?.sessionId as string;

  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, {
    categoryId: "cat_bowl",
    basePriceMinorUnits: 43000,
  });
  await seedChannelPricingPolicy(chain.restaurantId, { channelDefaultAdjustments: { takeaway: 2000 } });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      takeawaySessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const orderId = body.result?.orderId as string;
  const order = (await admin.firestore().collection("orders").doc(orderId).get()).data()!;
  assert.strictEqual(order.channel, "takeaway");
  assert.strictEqual(
    order.customerId,
    null,
    "must never become a CRM/customer order despite the real phone identity behind it",
  );
  assert.strictEqual(order.guestAuthUid, uid);
  assert.strictEqual(order.pickupMode, "asap");
  assert.strictEqual(order.pickupTime, null);
  assert.strictEqual(order.takeawayEntrySessionId, sessionId);
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 45000);
});

test("Faz D.4.1 (C): a real phone customer with NO valid guest session cannot fabricate a takeawaySessionId to imitate the QR guest path", async () => {
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      takeawaySessionId: "nonexistent-session-id",
      items: [{ kind: "product", productId: "irrelevant-product", quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 404);
  assert.strictEqual(body.error?.status, "NOT_FOUND");
});

test("Faz D.4.1 (C, cross-identity): a real phone customer cannot use a DIFFERENT caller's (anonymous guest's) session id — session ownership is identity-agnostic, not identity-type-agnostic", async () => {
  const chain = await seedValidChain();
  const token = await seedTakeawayQrCode(chain.restaurantId, chain.branchId, chain.organizationId);
  const anonGuest = await createAnonymousUser();
  const opened = await callCallable(OPEN_SESSION_URL, { token }, anonGuest.idToken);
  const sessionId = opened.body.result?.sessionId as string;

  const attacker = await createRealPhoneUser();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      takeawaySessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    attacker.idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("Faz D.4.1 (D): an anonymous caller with neither a takeawaySessionId nor authenticated-branch fields is denied — cannot reach either path", async () => {
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      items: [{ kind: "product", productId: "irrelevant-product", quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("Faz D.4.1 (F): submitting a QR guest order as an existing phone-verified customer never touches their underlying Firebase Auth identity or creates a CRM record", async () => {
  const chain = await seedValidChain();
  const token = await seedTakeawayQrCode(chain.restaurantId, chain.branchId, chain.organizationId);
  const { idToken, uid } = await createRealPhoneUser();
  const beforeUser = await admin.auth().getUser(uid);

  const opened = await callCallable(OPEN_SESSION_URL, { token }, idToken);
  const sessionId = opened.body.result?.sessionId as string;
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);

  const { httpStatus } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      takeawaySessionId: sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );
  assert.strictEqual(httpStatus, 200);

  const afterUser = await admin.auth().getUser(uid);
  assert.strictEqual(afterUser.uid, beforeUser.uid);
  assert.strictEqual(afterUser.phoneNumber, beforeUser.phoneNumber);
  assert.strictEqual(afterUser.providerData[0]?.providerId, "phone");

  // Mirrors openTakeawayGuestSession's own existing "no CRM/loyalty side
  // effect" contract — the guest order path must not create one either.
  const customerDoc = await admin.firestore().collection("customers").doc(uid).get();
  assert.strictEqual(customerDoc.exists, false);
});

// =======================================================================
// B. Authenticated customer scenarios
// =======================================================================

test("Authenticated: a real phone customer submits a valid scheduled order", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, {
    categoryId: "cat_bowl",
    basePriceMinorUnits: 43000,
  });
  await seedChannelPricingPolicy(chain.restaurantId, { channelDefaultAdjustments: { takeaway: 2000 } });
  const { idToken, uid } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const orderId = body.result?.orderId as string;
  const order = (await admin.firestore().collection("orders").doc(orderId).get()).data()!;
  assert.strictEqual(order.customerId, uid);
  assert.strictEqual(order.guestAuthUid, null);
  assert.strictEqual(order.pickupMode, "scheduled");
  assert.ok(order.pickupTime);
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 45000);
});

test("Authenticated: an anonymous technical identity attempting the authenticated-branch fields is rejected — spoof denied", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("Authenticated: pickup time exactly 19:59:59 from now (1 second under the 20-minute minimum) is rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: new Date(Date.now() + 19 * 60 * 1000 + 59 * 1000).toISOString(),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

test("Authenticated: pickup time exactly 20:00 from now is accepted (inclusive boundary)", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();

  const { httpStatus } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      // A few seconds of buffer beyond the exact boundary to absorb real
      // request latency between computing this value and the server
      // evaluating "now" — mirrors every other pickup-time test in this
      // codebase's own documented reasoning for the same phenomenon.
      pickupTime: new Date(Date.now() + 20 * 60 * 1000 + 5000).toISOString(),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
});

// =======================================================================
// C/D. Canonical pricing — beverage/normal/bowl
// =======================================================================

test("Pricing: a beverage (cat_icecekler, category override +0) is priced at basePrice unchanged", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, {
    categoryId: "cat_icecekler",
    basePriceMinorUnits: 4000,
  });
  await seedChannelPricingPolicy(chain.restaurantId, {
    channelDefaultAdjustments: { takeaway: 2000 },
    categoryOverrides: { takeaway: { cat_icecekler: 0 } },
  });
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 4000);
});

test("Pricing: a normal product gets +20 TL, and quantity 2 applies the adjustment twice (not once)", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, {
    categoryId: "cat_bowl",
    basePriceMinorUnits: 43000,
  });
  await seedChannelPricingPolicy(chain.restaurantId, { channelDefaultAdjustments: { takeaway: 2000 } });
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 2 }],
      ...CONTACT,
    },
    idToken,
  );

  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  // (43000+2000)*2 = 90000
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 90000);
});

test("Bowl: ingredient prices are canonical (client-sent bogus prices are never read at all), +20 applied exactly once, quantity 2 applies it twice — never once per ingredient", async () => {
  const chain = await seedValidChain();
  const chicken = nextId("ingredient");
  const rice = nextId("ingredient");
  const sauce = nextId("ingredient");
  await seedBowlIngredient(chicken, chain.restaurantId, chain.organizationId, { priceMinorUnits: 15000 });
  await seedBowlIngredient(rice, chain.restaurantId, chain.organizationId, { priceMinorUnits: 5000 });
  await seedBowlIngredient(sauce, chain.restaurantId, chain.organizationId, { priceMinorUnits: 2000 });
  await seedChannelPricingPolicy(chain.restaurantId, { channelDefaultAdjustments: { takeaway: 2000 } });
  const { idToken } = await createRealPhoneUser();

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
          quantity: 2,
          // A client-supplied "price" field on the bowl item itself — must
          // be completely ignored (there is no such field in the accepted
          // shape at all).
          price: 1,
          ingredientIds: [chicken, rice, sauce],
        },
      ],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  const line = order.lines[0];
  // ingredientTotal = 15000+5000+2000 = 22000; unitPrice(adjustment)=2000;
  // (2000+22000)*2 = 48000. If +20 were (incorrectly) applied per
  // ingredient instead, the total would be very different (48000 vs. a
  // per-ingredient-adjusted total like (2000*3+22000)*2=92000) — this
  // assertion distinguishes the two.
  assert.strictEqual(line.unitPrice.minorUnits, 2000, "the bowl's own unitPrice must be the +20 adjustment only");
  assert.strictEqual(
    line.modifiers.reduce((sum: number, m: any) => sum + m.unitExtraPrice.minorUnits, 0),
    22000,
  );
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 48000);
});

// =======================================================================
// E. Override precedence
// =======================================================================

test("Pricing overrides: explicitPrice wins over everything, including basePrice and any category/channel default", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, {
    basePriceMinorUnits: 25000,
    channelPriceOverrides: { takeaway: { type: "explicitPrice", priceMinorUnits: 59900 } },
  });
  await seedChannelPricingPolicy(chain.restaurantId, { channelDefaultAdjustments: { takeaway: 2000 } });
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );
  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 59900);
});

test("Pricing overrides: fixedAdjustment wins over the category/channel default", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, {
    basePriceMinorUnits: 15000,
    categoryId: "cat_atistirmalik",
    channelPriceOverrides: { takeaway: { type: "fixedAdjustment", adjustmentMinorUnits: 1000 } },
  });
  await seedChannelPricingPolicy(chain.restaurantId, {
    channelDefaultAdjustments: { takeaway: 2000 },
    categoryOverrides: { takeaway: { cat_atistirmalik: 3000 } },
  });
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );
  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 16000);
});

test("Pricing overrides: with no product-level override, a category override wins over the channel default", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, {
    basePriceMinorUnits: 10000,
    categoryId: "cat_icecekler",
  });
  await seedChannelPricingPolicy(chain.restaurantId, {
    channelDefaultAdjustments: { takeaway: 2000 },
    categoryOverrides: { takeaway: { cat_icecekler: 500 } },
  });
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );
  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 10500);
});

test("Pricing overrides: with no product or category override, the channel default applies", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, {
    basePriceMinorUnits: 10000,
    categoryId: "cat_wrap",
  });
  await seedChannelPricingPolicy(chain.restaurantId, { channelDefaultAdjustments: { takeaway: 2000 } });
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );
  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 12000);
});

// =======================================================================
// F. Manipulation / invalid input
// =======================================================================

test("Manipulation: a nonexistent productId is rejected", async () => {
  const chain = await seedValidChain();
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId: "product-that-does-not-exist", quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("Manipulation: an inactive product is rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { isAvailable: false });
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("Manipulation: a product belonging to a different restaurant (cross-tenant) is rejected", async () => {
  const chain = await seedValidChain();
  const otherChain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, otherChain.restaurantId, otherChain.organizationId);
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("Manipulation: a modifier not defined on the product is rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, {
    modifierGroups: [
      { id: "g1", name: "G1", selectionType: "single", isRequired: false, minSelections: 0, maxSelections: 1, options: [{ id: "o1", name: "O1", extraPriceMinorUnits: 500, isAvailable: true }] },
    ],
  });
  const { idToken } = await createRealPhoneUser();

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
          kind: "product",
          productId,
          quantity: 1,
          selectedModifiers: [{ groupId: "g1", optionId: "option-that-does-not-exist" }],
        },
      ],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("Manipulation: an inactive modifier option is rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, {
    modifierGroups: [
      { id: "g1", name: "G1", selectionType: "single", isRequired: false, minSelections: 0, maxSelections: 1, options: [{ id: "o1", name: "O1", extraPriceMinorUnits: 500, isAvailable: false }] },
    ],
  });
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [
        { kind: "product", productId, quantity: 1, selectedModifiers: [{ groupId: "g1", optionId: "o1" }] },
      ],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("Manipulation: a client-sent modifier extraPrice of 0 is ignored — the canonical modifier price is used instead", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, {
    basePriceMinorUnits: 10000,
    categoryId: "cat_wrap",
    modifierGroups: [
      { id: "g1", name: "G1", selectionType: "single", isRequired: false, minSelections: 0, maxSelections: 1, options: [{ id: "o1", name: "O1", extraPriceMinorUnits: 5000, isAvailable: true }] },
    ],
  });
  await seedChannelPricingPolicy(chain.restaurantId, { channelDefaultAdjustments: { takeaway: 0 } });
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [
        {
          kind: "product",
          productId,
          quantity: 1,
          // Attacker-controlled extraPrice — must be ignored entirely.
          selectedModifiers: [{ groupId: "g1", optionId: "o1", extraPrice: 0 }],
        },
      ],
      ...CONTACT,
    },
    idToken,
  );
  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  // basePrice 10000 + canonical modifier 5000 = 15000, not 10000.
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 15000);
});

test("Manipulation: claiming a different category on the item payload has no effect — the product's own canonical category is always used", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, {
    categoryId: "cat_icecekler",
    basePriceMinorUnits: 4000,
  });
  await seedChannelPricingPolicy(chain.restaurantId, {
    channelDefaultAdjustments: { takeaway: 2000 },
    categoryOverrides: { takeaway: { cat_icecekler: 0 } },
  });
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [
        // categoryId is not part of the accepted item shape at all — sent
        // here only to prove it's a no-op even if present.
        { kind: "product", productId, quantity: 1, categoryId: "cat_bowl" },
      ],
      ...CONTACT,
    },
    idToken,
  );
  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 4000, "must still resolve as a beverage (+0), not a bowl (+20)");
});

test("Manipulation: a client-sent unitPrice/price field on the item is never read — canonical pricing always wins", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, {
    basePriceMinorUnits: 10000,
    categoryId: "cat_wrap",
  });
  await seedChannelPricingPolicy(chain.restaurantId, { channelDefaultAdjustments: { takeaway: 2000 } });
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1, unitPrice: 1, price: 1 }],
      ...CONTACT,
    },
    idToken,
  );
  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 12000);
});

test("Manipulation: quantity <= 0 is rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 0 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("Manipulation: an excessive quantity is rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 999 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

// =======================================================================
// G. Idempotency
// =======================================================================

test("Idempotency: the same request (same actor, same key, same payload) submitted twice produces exactly one order", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const { idToken } = await createRealPhoneUser();
  const submissionKey = nextId("key");
  const payload = {
    submissionKey,
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    pickupMode: "scheduled",
    pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }],
    ...CONTACT,
  };

  const first = await callCallable(SUBMIT_URL, payload, idToken);
  const second = await callCallable(SUBMIT_URL, payload, idToken);

  assert.strictEqual(first.body.result?.orderId, second.body.result?.orderId);
  assert.strictEqual(first.body.result?.duplicate, false);
  assert.strictEqual(second.body.result?.duplicate, true);
  const orders = await admin.firestore().collection("orders").where("orderId", "==", first.body.result!.orderId).get();
  assert.strictEqual(orders.size, 1);
});

test("Idempotency: reusing the same submissionKey with a different payload is rejected fail-closed — no second order, original untouched", async () => {
  const chain = await seedValidChain();
  const productA = nextId("product");
  const productB = nextId("product");
  await seedMenuProduct(productA, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  await seedMenuProduct(productB, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 99999 });
  const { idToken } = await createRealPhoneUser();
  const submissionKey = nextId("key");

  const first = await callCallable(
    SUBMIT_URL,
    {
      submissionKey,
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId: productA, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );
  const second = await callCallable(
    SUBMIT_URL,
    {
      submissionKey,
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId: productB, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(second.httpStatus, 400);
  assert.strictEqual(second.body.error?.status, "FAILED_PRECONDITION");

  const order = (await admin.firestore().collection("orders").doc(first.body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.lines[0].productId, productA, "the original order must be untouched by the rejected retry");
});

test("Idempotency: two different actors using the identical submissionKey get two fully independent orders", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const customerA = await createRealPhoneUser();
  const customerB = await createRealPhoneUser();
  const sharedKey = nextId("key");
  const payloadFor = () => ({
    submissionKey: sharedKey,
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    pickupMode: "scheduled",
    pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }],
    ...CONTACT,
  });

  const resultA = await callCallable(SUBMIT_URL, payloadFor(), customerA.idToken);
  const resultB = await callCallable(SUBMIT_URL, payloadFor(), customerB.idToken);

  assert.strictEqual(resultA.httpStatus, 200);
  assert.strictEqual(resultB.httpStatus, 200);
  assert.notStrictEqual(resultA.body.result?.orderId, resultB.body.result?.orderId);
});

// =======================================================================
// C. Boncuk Loyalty P4-B — checkout redemption (authenticated takeaway
// only; delivery/reservation/dineInQr/POS are out of scope this phase).
// "Boncuk is settlement, not discount" (P4-A, accepted) — pricing.discount
// and pricing.grandTotal are asserted UNCHANGED by every redemption test
// below; only the parallel boncukRedemption snapshot reflects it.
// =======================================================================

test("Redemption: no requestedBoncukAmount -> selectedBenefitType 'none', boncukRedemption null, unchanged pricing", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.selectedBenefitType, "none");
  assert.strictEqual(order.boncukRedemption, null);
  assert.strictEqual(order.pricing.discount.minorUnits, 0);
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 50000);
});

test("Redemption: a valid within-caps request settles part of the (unchanged) total, debits the account, and writes a ledger entry", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 400 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
      requestedBoncukAmount: 120,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const orderId = body.result!.orderId as string;
  const order = (await admin.firestore().collection("orders").doc(orderId).get()).data()!;

  // Settlement, not discount — the order's own price fields are untouched.
  assert.strictEqual(order.pricing.discount.minorUnits, 0);
  assert.strictEqual(order.pricing.grandTotal.minorUnits, 50000);

  assert.strictEqual(order.selectedBenefitType, "boncukRedemption");
  assert.strictEqual(order.boncukRedemption.boncukUsed, 120);
  assert.strictEqual(order.boncukRedemption.valueMinorUnits, 12000);
  assert.strictEqual(order.boncukRedemption.remainingPayableMinorUnits, 38000);
  assert.strictEqual(order.boncukRedemption.redemptionValueMinorUnitsPerBoncuk, 100);
  assert.strictEqual(order.boncukRedemption.maxRedemptionBasisPoints, 5000);
  assert.strictEqual(order.boncukRedemption.loyaltyPolicyVersion, 1);

  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 280);
  assert.strictEqual(account?.lifetimeRedeemed, 120);
  assert.strictEqual(account?.boncukDebt, 0);
  assert.strictEqual(account?.revision, 2);

  const ledger = await boncukRedemptionLedgerDoc(chain.organizationId, uid, orderId);
  assert.ok(ledger);
  assert.strictEqual(ledger?.entryType, "boncukRedemption");
  assert.strictEqual(ledger?.entitlementDeltaBoncuk, 0);
  assert.strictEqual(ledger?.spendableDeltaBoncuk, -120);
  assert.strictEqual(ledger?.debtDeltaBoncuk, 0);
  assert.strictEqual(ledger?.amountBasisMinorUnits, 12000);
  assert.strictEqual(ledger?.redemptionValueMinorUnitsPerBoncuk, 100);
  assert.strictEqual(ledger?.maxRedemptionBasisPoints, 5000);
  assert.strictEqual(ledger?.loyaltyPolicyVersion, 1);
  assert.strictEqual(ledger?.sourceId, orderId);
  assert.strictEqual(ledger?.orderId, orderId);
  assert.strictEqual(ledger?.organizationId, chain.organizationId);
  assert.strictEqual(ledger?.customerId, uid);
  assert.strictEqual(ledger?.idempotencyKey, orderId);
  assert.strictEqual(ledger?.reversalOf, null);
});

test("Redemption: exactly at the order-cap boundary succeeds", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 4000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 100 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
      requestedBoncukAmount: 20,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200);
  const order = (await admin.firestore().collection("orders").doc(body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.boncukRedemption.boncukUsed, 20);
  assert.strictEqual(order.boncukRedemption.valueMinorUnits, 2000);
  assert.strictEqual(order.boncukRedemption.remainingPayableMinorUnits, 2000);
});

test("Redemption: one Boncuk over the order cap is rejected outright, never clamped, no order/account/ledger mutation", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 4000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 100 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
      requestedBoncukAmount: 21,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 100, "the account must be untouched by a rejected request");
  const orders = await admin.firestore().collection("orders").where("customerId", "==", uid).get();
  assert.strictEqual(orders.size, 0);
});

test("Redemption: a request exceeding the spendable balance (but within the order cap) is rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 50 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
      requestedBoncukAmount: 60,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 50);
});

test("Redemption: no loyalty account exists for the customer -> rejected, fails safely", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const { idToken, uid } = await createRealPhoneUser();
  // Deliberately no seedLoyaltyAccount call.

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
      requestedBoncukAmount: 10,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const orders = await admin.firestore().collection("orders").where("customerId", "==", uid).get();
  assert.strictEqual(orders.size, 0);
});

test("Redemption: a guest (QR) takeaway request with requestedBoncukAmount > 0 is rejected outright, never silently ignored", async () => {
  const session = await seedGuestSession();
  const productId = nextId("product");
  await seedMenuProduct(productId, session.restaurantId, session.organizationId, { basePriceMinorUnits: 50000 });

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      takeawaySessionId: session.sessionId,
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
      requestedBoncukAmount: 1,
    },
    session.idToken,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
  const orders = await admin.firestore().collection("orders").where("guestAuthUid", "==", session.uid).get();
  assert.strictEqual(orders.size, 0);
});

test("Redemption: requestedBoncukAmount must be a non-negative integer — a fractional value is rejected", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      pickupMode: "scheduled",
      pickupTime: futurePickupIso(30),
      items: [{ kind: "product", productId, quantity: 1 }],
      ...CONTACT,
      requestedBoncukAmount: 1.5,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

// -----------------------------------------------------------------------
// C.1 Idempotency — the existing submissionKey/fingerprint retry mechanism
// must correctly cover redemption too (P4-B §10).
// -----------------------------------------------------------------------

test("Redemption idempotency: retrying the identical submissionKey + identical requestedBoncukAmount is a no-op the second time — no double debit, no double ledger entry", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 100 });

  const payload = {
    submissionKey: nextId("key"),
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    pickupMode: "scheduled",
    pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }],
    ...CONTACT,
    requestedBoncukAmount: 10,
  };

  const first = await callCallable(SUBMIT_URL, payload, idToken);
  const second = await callCallable(SUBMIT_URL, payload, idToken);

  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.duplicate, true);
  assert.strictEqual(first.body.result?.orderId, second.body.result?.orderId);

  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 90, "a retry must never debit the account a second time");
  assert.strictEqual(account?.lifetimeRedeemed, 10);
  assert.strictEqual(account?.revision, 2, "a retry must never bump revision a second time");
});

test("Redemption idempotency: reusing the same submissionKey with a DIFFERENT requestedBoncukAmount fails closed and never mutates the already-created order", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 100 });

  const submissionKey = nextId("key");
  const basePayload = {
    submissionKey,
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    pickupMode: "scheduled",
    pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }],
    ...CONTACT,
  };

  const first = await callCallable(SUBMIT_URL, { ...basePayload, requestedBoncukAmount: 10 }, idToken);
  const second = await callCallable(SUBMIT_URL, { ...basePayload, requestedBoncukAmount: 20 }, idToken);

  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(second.httpStatus, 400);
  assert.strictEqual(second.body.error?.status, "FAILED_PRECONDITION");

  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 90, "the rejected retry must never debit the account a second time");

  const order = (await admin.firestore().collection("orders").doc(first.body.result!.orderId as string).get()).data()!;
  assert.strictEqual(order.boncukRedemption.boncukUsed, 10, "the original order must be untouched by the rejected retry");
});

// -----------------------------------------------------------------------
// C.2 Double-spend protection (P4-B §9) — the balance check must be
// inside the authoritative transaction, proven under real concurrency.
// -----------------------------------------------------------------------

test("Redemption double-spend: two concurrent requests for 15 Boncuk each, against a balance of 20, must not both succeed", async () => {
  const chain = await seedValidChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 50000 });
  const { idToken, uid } = await createRealPhoneUser();
  await seedLoyaltyAccount(chain.organizationId, uid, { spendableBalance: 20 });

  const payloadFor = () => ({
    submissionKey: nextId("key"),
    restaurantId: chain.restaurantId,
    branchId: chain.branchId,
    pickupMode: "scheduled",
    pickupTime: futurePickupIso(30),
    items: [{ kind: "product", productId, quantity: 1 }],
    ...CONTACT,
    requestedBoncukAmount: 15,
  });

  const [resultA, resultB] = await Promise.all([
    callCallable(SUBMIT_URL, payloadFor(), idToken),
    callCallable(SUBMIT_URL, payloadFor(), idToken),
  ]);

  const successes = [resultA, resultB].filter((r) => r.httpStatus === 200);
  const failures = [resultA, resultB].filter((r) => r.httpStatus !== 200);
  assert.strictEqual(successes.length, 1, "exactly one of the two concurrent 15-Boncuk requests must succeed");
  assert.strictEqual(failures.length, 1);
  assert.strictEqual(failures[0].body.error?.status, "INVALID_ARGUMENT");

  const account = await loyaltyAccountDoc(chain.organizationId, uid);
  assert.strictEqual(account?.spendableBalance, 5, "the balance must reflect exactly one debit, never negative, never double-debited");
  assert.strictEqual(account?.lifetimeRedeemed, 15);
});
