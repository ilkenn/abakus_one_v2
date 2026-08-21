import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { slugifyAddressComponent } from "../deliveryServiceAreas";

/**
 * Emulator-backed adversarial tests for `submitDeliveryOrder` /
 * `checkDeliveryEligibility` — Paket Servis P.3. Mirrors
 * `submitTakeawayOrder.test.ts`'s exact pattern (raw HTTP against the
 * callable-functions wire protocol, real Firestore fixtures seeded
 * directly via the Admin SDK, real phone-auth via the Auth emulator for
 * `isRealCustomer`).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SUBMIT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/submitDeliveryOrder`;
const ELIGIBILITY_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/checkDeliveryEligibility`;

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
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken: string; localId: string };
  return { idToken: body.idToken, uid: body.localId };
}

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

let idCounter = 0;
function nextId(prefix: string): string {
  idCounter += 1;
  return `${prefix}-${TEST_RUN_ID}-${idCounter}`;
}

const db = () => admin.firestore();

async function seedChain() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  await db().collection("organizations").doc(organizationId).set({ name: "Test", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  await db().collection("branches").doc(branchId).set({
    restaurantId, organizationId, name: "Merkez Şube", status: "active",
    emergencyStopped: false, supportedOrderChannelIds: ["delivery"],
  });
  return { organizationId, restaurantId, branchId };
}

async function seedChannelPricingPolicy(restaurantId: string) {
  // The exact LOCKED Faz P.1 delivery rule: +140 default, +20 drinks.
  await db().collection("channelPricingPolicies").doc(restaurantId).set({
    channelDefaultAdjustments: { delivery: 14000 },
    categoryOverrides: { delivery: { cat_icecekler: 2000 } },
  });
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

async function seedBowlIngredient(
  id: string,
  restaurantId: string,
  organizationId: string,
  overrides: Partial<{ priceMinorUnits: number; isAvailable: boolean }> = {},
) {
  await db().collection("bowlIngredients").doc(id).set({
    organizationId, restaurantId, categoryId: "protein", name: "Test Ingredient",
    priceMinorUnits: overrides.priceMinorUnits ?? 5000,
    isAvailable: overrides.isAvailable ?? true,
  });
}

async function seedDeliveryServiceArea(
  chain: { organizationId: string; restaurantId: string; branchId: string },
  districtId: string,
  neighborhoodId: string,
  overrides: Partial<{ enabled: boolean; minimumOrderMinorUnits: number }> = {},
) {
  await db().collection("deliveryServiceAreas").doc(nextId("area")).set({
    organizationId: chain.organizationId, branchId: chain.branchId, restaurantId: chain.restaurantId,
    districtId, neighborhoodId,
    enabled: overrides.enabled ?? true,
    minimumOrderMinorUnits: overrides.minimumOrderMinorUnits ?? 0,
  });
}

async function seedCustomerAddress(
  uid: string,
  overrides: Partial<{
    districtName: string; neighborhoodName: string; verificationStatus: string;
    latitude: number; longitude: number;
  }> = {},
): Promise<string> {
  const addressId = nextId("address");
  const now = new Date().toISOString();
  await db().collection("customerAddresses").doc(addressId).set({
    uid,
    label: "Ev",
    provinceName: "İstanbul",
    districtName: overrides.districtName ?? "Beşiktaş",
    neighborhoodName: overrides.neighborhoodName ?? "Levent",
    streetName: "Test Sk.",
    buildingNo: "1",
    buildingNoSource: "provider",
    apartmentNo: "4",
    floor: "2",
    addressDescription: null,
    latitude: overrides.latitude ?? 41.05,
    longitude: overrides.longitude ?? 29.01,
    verificationStatus: overrides.verificationStatus ?? "verified",
    verifiedAt: overrides.verificationStatus === "unverified" ? null : now,
    providerSource: "google_places",
    providerPlaceId: "test-place-id",
    isDefault: false,
    formattedAddress: "Test Address",
  });
  return addressId;
}

/**
 * Full valid fixture: chain + drink product + standard product + bowl
 * ingredient + pricing policy + covered service area + verified address.
 *
 * Each call mints its OWN unique neighborhood name (never a fixed
 * "Levent") so that repeated calls across tests never produce two
 * `deliveryServiceAreas` documents matching the same (districtId,
 * neighborhoodId) pair — which `resolveDeliveryServiceArea` correctly (and
 * intentionally) treats as an ambiguous, fail-closed match. This mirrors
 * real production risk (two overlapping zone configs for the same area)
 * rather than working around it, so each fixture gets its own zone.
 */
async function seedFullValidFixture(overrides: { minimumOrderMinorUnits?: number } = {}) {
  const chain = await seedChain();
  await seedChannelPricingPolicy(chain.restaurantId);
  const drinkProductId = nextId("drink");
  const standardProductId = nextId("standard");
  const bowlIngredientId = nextId("ingredient");
  await seedMenuProduct(drinkProductId, chain.restaurantId, chain.organizationId, {
    categoryId: "cat_icecekler", basePriceMinorUnits: 3000,
  });
  await seedMenuProduct(standardProductId, chain.restaurantId, chain.organizationId, {
    categoryId: "cat_standard", basePriceMinorUnits: 10000,
  });
  await seedBowlIngredient(bowlIngredientId, chain.restaurantId, chain.organizationId, {
    priceMinorUnits: 5000,
  });
  const districtName = "Beşiktaş";
  const neighborhoodName = `Levent ${nextId("zone")}`;
  const districtId = slugifyAddressComponent(districtName);
  const neighborhoodId = slugifyAddressComponent(neighborhoodName);
  await seedDeliveryServiceArea(chain, districtId, neighborhoodId, {
    minimumOrderMinorUnits: overrides.minimumOrderMinorUnits ?? 0,
  });
  const { idToken, uid } = await createRealPhoneUser();
  const savedAddressId = await seedCustomerAddress(uid, { districtName, neighborhoodName });
  return { chain, drinkProductId, standardProductId, bowlIngredientId, idToken, uid, savedAddressId };
}

function validSubmission(overrides: Record<string, unknown> = {}): Record<string, unknown> {
  return {
    submissionKey: nextId("key"),
    paymentMethodId: "cash",
    ...overrides,
  };
}

async function fraudEvidenceForOrder(orderId: string) {
  const doc = await db().collection("fraudEvidence").doc(`${orderId}-order-submit-evidence`).get();
  return doc.exists ? doc.data()! : null;
}
async function riskContextForOrder(orderId: string) {
  const doc = await db().collection("fraudRiskContexts").doc(`${orderId}-risk-context`).get();
  return doc.exists ? doc.data()! : null;
}

// =======================================================================
// AUTH
// =======================================================================

test("submitDeliveryOrder: an unauthenticated caller is rejected", async () => {
  const { body } = await callCallable(SUBMIT_URL, validSubmission({ savedAddressId: "x", items: [] }));
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("submitDeliveryOrder: an anonymous (guest/table-guest-shaped) identity is denied — no guest delivery ordering exists", async () => {
  const fixture = await seedFullValidFixture();
  const anon = await createAnonymousUser();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    anon.idToken,
  );
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("submitDeliveryOrder: an authenticated real phone customer is allowed (happy path)", async () => {
  const fixture = await seedFullValidFixture();
  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.duplicate, false);
});

test("submitDeliveryOrder: a forged customerId/uid in the payload is ignored — the real authenticated uid is authoritative", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      customerId: "someone-else",
      uid: "someone-else",
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const order = await db().collection("orders").doc(orderId).get();
  assert.strictEqual(order.data()?.customerId, fixture.uid);
});

test("submitDeliveryOrder: the order carries the exact canonical server pricing-authority marker, and a request-payload override attempt is ignored (Boncuk Loyalty P2A security fix, 2026-08-21)", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      pricingAuthority: "client-forged-value",
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const order = await db().collection("orders").doc(orderId).get();
  assert.strictEqual(order.data()?.pricingAuthority, "serverV1");
});

// =======================================================================
// ADDRESS
// =======================================================================

test("submitDeliveryOrder: an address belonging to another user is denied", async () => {
  const fixture = await seedFullValidFixture();
  const other = await createRealPhoneUser();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    other.idToken,
  );
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("submitDeliveryOrder: forged address coordinates in the payload are never read — only savedAddressId matters", async () => {
  const fixture = await seedFullValidFixture();
  const { httpStatus } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      latitude: 0,
      longitude: 0,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 200); // succeeds using the REAL address, forged fields simply unread
});

test("submitDeliveryOrder: forged district/neighborhood in the payload are never read — the authoritative address's own district is used", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      districtId: "some_unserved_district",
      neighborhoodId: "some_unserved_neighborhood",
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const order = await db().collection("orders").doc(orderId).get();
  assert.strictEqual(order.data()?.deliveryAddressSnapshot?.districtName, "Beşiktaş");
});

test("submitDeliveryOrder: a disabled service-area neighborhood is denied", async () => {
  const chain = await seedChain();
  await seedChannelPricingPolicy(chain.restaurantId);
  const productId = nextId("standard");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const districtId = slugifyAddressComponent("Şişli");
  const neighborhoodId = slugifyAddressComponent("Mecidiyeköy");
  await seedDeliveryServiceArea(chain, districtId, neighborhoodId, { enabled: false });
  const { idToken, uid } = await createRealPhoneUser();
  const savedAddressId = await seedCustomerAddress(uid, { districtName: "Şişli", neighborhoodName: "Mecidiyeköy" });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({ savedAddressId, items: [{ kind: "product", productId, quantity: 1 }] }),
    idToken,
  );
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  assert.match(String(body.error?.message), /paket servis hizmeti veremiyoruz/);
});

test("submitDeliveryOrder: minimum order is server-enforced against the real computed subtotal", async () => {
  const fixture = await seedFullValidFixture({ minimumOrderMinorUnits: 50000 }); // 500 TL minimum
  const belowMin = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }], // ~240 TL
    }),
    fixture.idToken,
  );
  assert.strictEqual(belowMin.body.error?.status, "FAILED_PRECONDITION");
  assert.match(String(belowMin.body.error?.message), /Minimum sipariş/);

  const aboveMin = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 5 }], // ~1200 TL
    }),
    fixture.idToken,
  );
  assert.strictEqual(aboveMin.httpStatus, 200);
});

test("submitDeliveryOrder: an address with no matching service area at all is denied — no 'all Istanbul is covered' fallback exists", async () => {
  const chain = await seedChain();
  await seedChannelPricingPolicy(chain.restaurantId);
  const productId = nextId("standard");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  // Deliberately seed ZERO deliveryServiceAreas documents for this address.
  const { idToken, uid } = await createRealPhoneUser();
  const savedAddressId = await seedCustomerAddress(uid, {
    districtName: "Hiçbiryerde", neighborhoodName: "Olmayan Mahalle",
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({ savedAddressId, items: [{ kind: "product", productId, quantity: 1 }] }),
    idToken,
  );
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  assert.match(String(body.error?.message), /paket servis hizmeti veremiyoruz/);
});

test("submitDeliveryOrder: an unverified address is denied even if a service area matches", async () => {
  const chain = await seedChain();
  await seedChannelPricingPolicy(chain.restaurantId);
  const productId = nextId("standard");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId);
  const districtId = slugifyAddressComponent("Beyoğlu");
  const neighborhoodId = slugifyAddressComponent("Cihangir");
  await seedDeliveryServiceArea(chain, districtId, neighborhoodId);
  const { idToken, uid } = await createRealPhoneUser();
  const savedAddressId = await seedCustomerAddress(uid, {
    districtName: "Beyoğlu", neighborhoodName: "Cihangir", verificationStatus: "unverified",
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({ savedAddressId, items: [{ kind: "product", productId, quantity: 1 }] }),
    idToken,
  );
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});

// =======================================================================
// PRICING
// =======================================================================

test("submitDeliveryOrder: a forged client total/price is entirely ignored — server computes the real total", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      grandTotal: 1,
      subtotal: 1,
      items: [
        { kind: "product", productId: fixture.standardProductId, quantity: 1, unitPrice: 1, lineTotal: 1 },
      ],
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const order = await db().collection("orders").doc(orderId).get();
  // Base 10000 + 14000 (standard delivery adjustment) = 24000 minor units.
  assert.strictEqual(order.data()?.pricing?.grandTotal?.minorUnits, 24000);
});

test("submitDeliveryOrder: a drink product receives exactly the +20 TL delivery adjustment", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.drinkProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const order = await db().collection("orders").doc(orderId).get();
  const lines = order.data()?.lines as { unitPrice: { minorUnits: number } }[];
  // Base 3000 + 2000 (drink override) = 5000 minor units.
  assert.strictEqual(lines[0].unitPrice.minorUnits, 5000);
});

test("submitDeliveryOrder: a standard product receives exactly the +140 TL delivery adjustment", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const order = await db().collection("orders").doc(orderId).get();
  const lines = order.data()?.lines as { unitPrice: { minorUnits: number } }[];
  // Base 10000 + 14000 (standard default) = 24000 minor units.
  assert.strictEqual(lines[0].unitPrice.minorUnits, 24000);
});

test("submitDeliveryOrder: multiple quantity is handled correctly (lineTotal = unitPrice * quantity)", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 3 }],
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const order = await db().collection("orders").doc(orderId).get();
  assert.strictEqual(order.data()?.pricing?.grossSubtotal?.minorUnits, 24000 * 3);
});

test("submitDeliveryOrder: Bowl Builder receives the +140 TL adjustment exactly ONCE per bowl, never per ingredient", async () => {
  const fixture = await seedFullValidFixture();
  const secondIngredientId = nextId("ingredient2");
  await seedBowlIngredient(secondIngredientId, fixture.chain.restaurantId, fixture.chain.organizationId, {
    priceMinorUnits: 3000,
  });
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [
        {
          kind: "bowl",
          quantity: 1,
          ingredientIds: [fixture.bowlIngredientId, secondIngredientId],
        },
      ],
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const order = await db().collection("orders").doc(orderId).get();
  const lines = order.data()?.lines as {
    unitPrice: { minorUnits: number };
    modifiers: { unitExtraPrice: { minorUnits: number } }[];
  }[];
  // Bowl unitPrice is the +140 channel adjustment ONLY — never multiplied
  // by ingredient count, never added per-ingredient.
  assert.strictEqual(lines[0].unitPrice.minorUnits, 14000);
  // Ingredient prices live entirely in modifiers, summing to 5000+3000.
  const modifierSum = lines[0].modifiers.reduce((s, m) => s + m.unitExtraPrice.minorUnits, 0);
  assert.strictEqual(modifierSum, 8000);
});

test("submitDeliveryOrder: ingredient-level surcharge manipulation is impossible — forged ingredient prices in the payload are ignored", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [
        {
          kind: "bowl",
          quantity: 1,
          ingredientIds: [fixture.bowlIngredientId],
          ingredientPrices: { [fixture.bowlIngredientId]: 1 }, // forged, never read
        },
      ],
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const order = await db().collection("orders").doc(orderId).get();
  const lines = order.data()?.lines as { modifiers: { unitExtraPrice: { minorUnits: number } }[] }[];
  assert.strictEqual(lines[0].modifiers[0].unitExtraPrice.minorUnits, 5000); // the real, seeded price
});

test("submitDeliveryOrder: prices are always freshly resolved, never stale/cached — a price change is reflected on the next distinct submission", async () => {
  const fixture = await seedFullValidFixture();
  const first = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  const firstOrder = await db().collection("orders").doc(first.body.result?.orderId as string).get();
  assert.strictEqual(firstOrder.data()?.lines[0].unitPrice.minorUnits, 24000);

  await db().collection("menuProducts").doc(fixture.standardProductId).update({ basePriceMinorUnits: 20000 });

  const second = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  const secondOrder = await db().collection("orders").doc(second.body.result?.orderId as string).get();
  assert.strictEqual(secondOrder.data()?.lines[0].unitPrice.minorUnits, 34000); // 20000 + 14000
});

// =======================================================================
// PAYMENT
// =======================================================================

test("submitDeliveryOrder: exactly the 7 LOCKED delivery payment methods are accepted", async () => {
  const methods = ["cash", "credit_card", "pluxee", "multinet", "setcard", "edenred", "metropol_card"];
  for (const paymentMethodId of methods) {
    const fixture = await seedFullValidFixture();
    const { httpStatus } = await callCallable(
      SUBMIT_URL,
      validSubmission({
        savedAddressId: fixture.savedAddressId,
        paymentMethodId,
        items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      }),
      fixture.idToken,
    );
    assert.strictEqual(httpStatus, 200, `expected ${paymentMethodId} to be accepted`);
  }
});

test("submitDeliveryOrder: an online-card-shaped or excluded payment method is denied", async () => {
  const fixture = await seedFullValidFixture();
  for (const paymentMethodId of ["online_card", "bank_transfer", "gift_voucher"]) {
    const { body } = await callCallable(
      SUBMIT_URL,
      validSubmission({
        savedAddressId: fixture.savedAddressId,
        paymentMethodId,
        items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      }),
      fixture.idToken,
    );
    assert.strictEqual(body.error?.status, "INVALID_ARGUMENT", `expected ${paymentMethodId} to be denied`);
  }
});

test("submitDeliveryOrder: an arbitrary/garbage payment method id is denied", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      paymentMethodId: "forged-nonexistent-method",
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("submitDeliveryOrder: an immutable payment-method snapshot is created with the correct real metadata", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      paymentMethodId: "pluxee",
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const order = await db().collection("orders").doc(orderId).get();
  const snapshot = order.data()?.paymentMethodSnapshot;
  assert.strictEqual(snapshot.paymentMethodId, "pluxee");
  assert.strictEqual(snapshot.displayName, "Pluxee");
  assert.strictEqual(snapshot.reportingCategory, "mealCard");
  assert.strictEqual(snapshot.providerId, "pluxee");
});

// =======================================================================
// ORDER
// =======================================================================

test("submitDeliveryOrder: organization/branch/restaurant scope is authoritative — a forged branchId/restaurantId in the payload is never read", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      branchId: "forged-branch",
      restaurantId: "forged-restaurant",
      organizationId: "forged-org",
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const order = await db().collection("orders").doc(orderId).get();
  assert.strictEqual(order.data()?.branchId, fixture.chain.branchId);
  assert.strictEqual(order.data()?.restaurantId, fixture.chain.restaurantId);
  assert.strictEqual(order.data()?.organizationId, fixture.chain.organizationId);
});

test("submitDeliveryOrder: the delivery address snapshot is immutable — a later SavedAddress edit never changes a historical order", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const orderBefore = await db().collection("orders").doc(orderId).get();
  const snapshotBefore = orderBefore.data()?.deliveryAddressSnapshot;
  assert.strictEqual(snapshotBefore.label, "Ev");
  assert.strictEqual(snapshotBefore.apartmentNo, "4");

  await db().collection("customerAddresses").doc(fixture.savedAddressId).update({
    label: "İş (değiştirildi)",
    apartmentNo: "99",
  });

  const orderAfter = await db().collection("orders").doc(orderId).get();
  const snapshotAfter = orderAfter.data()?.deliveryAddressSnapshot;
  assert.strictEqual(snapshotAfter.label, "Ev", "historical order snapshot must not change");
  assert.strictEqual(snapshotAfter.apartmentNo, "4", "historical order snapshot must not change");
});

test("submitDeliveryOrder: replaying the same submissionKey with the same payload is idempotent — no duplicate order/evidence/risk-context", async () => {
  const fixture = await seedFullValidFixture();
  const submission = validSubmission({
    savedAddressId: fixture.savedAddressId,
    items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
  });
  const first = await callCallable(SUBMIT_URL, submission, fixture.idToken);
  const second = await callCallable(SUBMIT_URL, submission, fixture.idToken);

  assert.strictEqual(first.body.result?.duplicate, false);
  assert.strictEqual(second.body.result?.duplicate, true);
  assert.strictEqual(first.body.result?.orderId, second.body.result?.orderId);

  const orderId = first.body.result?.orderId as string;
  const evidenceSnap = await db()
    .collection("fraudEvidence")
    .where("orderId", "==", orderId)
    .get();
  assert.strictEqual(evidenceSnap.docs.length, 1, "must never create a second FraudEvidence on replay");
  const riskSnap = await db().collection("fraudRiskContexts").where("orderId", "==", orderId).get();
  assert.strictEqual(riskSnap.docs.length, 1, "must never create a second FraudRiskContext on replay");
});

test("submitDeliveryOrder: reusing the same submissionKey with a DIFFERENT payload is rejected, not silently accepted", async () => {
  const fixture = await seedFullValidFixture();
  const submissionKey = nextId("key");
  const first = await callCallable(
    SUBMIT_URL,
    { submissionKey, paymentMethodId: "cash", savedAddressId: fixture.savedAddressId, items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }] },
    fixture.idToken,
  );
  assert.strictEqual(first.httpStatus, 200);

  const second = await callCallable(
    SUBMIT_URL,
    { submissionKey, paymentMethodId: "cash", savedAddressId: fixture.savedAddressId, items: [{ kind: "product", productId: fixture.standardProductId, quantity: 5 }] },
    fixture.idToken,
  );
  assert.strictEqual(second.body.error?.status, "FAILED_PRECONDITION");
});

// =======================================================================
// FRAUD-F.2
// =======================================================================

test("FRAUD-F.2: a fresh order-submit location candidate produces available FraudEvidence with the order's own tenant scope", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      deviceLocationCandidate: {
        status: "available",
        latitude: 41.06,
        longitude: 29.02,
        accuracyMeters: 12,
        clientCapturedAt: "2026-08-16T10:00:00.000Z",
        mockLocationStatus: "notDetected",
        permissionState: "granted",
        precisionState: "precise",
      },
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const evidence = await fraudEvidenceForOrder(orderId);
  assert.strictEqual(evidence?.kind, "orderSubmit");
  assert.strictEqual(evidence?.availability, "available");
  assert.strictEqual(evidence?.subjectUid, fixture.uid);
  assert.strictEqual(evidence?.orderId, orderId);
  assert.strictEqual(evidence?.organizationId, fixture.chain.organizationId);
  assert.strictEqual(evidence?.branchId, fixture.chain.branchId);
});

test("FRAUD-F.2: no device-location candidate never fabricates coordinates — recorded as unavailable, order still succeeds", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  assert.strictEqual(body.error, undefined);
  const orderId = body.result?.orderId as string;
  const evidence = await fraudEvidenceForOrder(orderId);
  assert.strictEqual(evidence?.availability, "unavailable");
  assert.strictEqual(evidence?.clientLocation, null);
});

test("FRAUD-F.2: a valid prior addressSave evidence for the same (subjectUid, savedAddressId) is linked via priorEvidenceId", async () => {
  const fixture = await seedFullValidFixture();
  const priorId = nextId("prior-evidence");
  await db().collection("fraudEvidence").doc(priorId).set({
    id: priorId, kind: "addressSave", subjectUid: fixture.uid, savedAddressId: fixture.savedAddressId,
    organizationId: null, branchId: null, orderId: null,
    availability: "unavailable", clientLocation: null, unavailableReason: "not_supplied",
    serverReceivedAt: new Date().toISOString(), createdAt: new Date().toISOString(), expiresAt: null,
    interpretation: {},
  });

  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const evidence = await fraudEvidenceForOrder(orderId);
  assert.strictEqual(evidence?.priorEvidenceId, priorId);

  // The prior evidence itself is never mutated.
  const priorAfter = await db().collection("fraudEvidence").doc(priorId).get();
  assert.strictEqual(priorAfter.data()?.availability, "unavailable");
  assert.strictEqual(priorAfter.data()?.orderId, null);
});

test("FRAUD-F.2: no matching prior addressSave evidence is tolerated — priorEvidenceId is null, order still valid", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  assert.strictEqual(body.error, undefined);
  const orderId = body.result?.orderId as string;
  const evidence = await fraudEvidenceForOrder(orderId);
  assert.strictEqual(evidence?.priorEvidenceId, null);
});

test("FRAUD-F.2: client-forged distanceMeters/riskScore/appCheckState/policyVersion/tenant ids are never honored", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      // Forged at the top level and inside the candidate itself.
      distanceMeters: 0,
      riskScore: 0,
      riskLevel: "none",
      fraudStatus: "clean",
      phoneVerificationState: true,
      appCheckState: "VERIFIED",
      trustedDevice: true,
      policyVersion: "forged-v99",
      organizationId: "forged-org",
      branchId: "forged-branch",
      deviceLocationCandidate: {
        status: "available",
        latitude: 41.06,
        longitude: 29.02,
        accuracyMeters: 12,
        clientCapturedAt: "2026-08-16T10:00:00.000Z",
        mockLocationStatus: "notDetected",
        permissionState: "granted",
        precisionState: "precise",
        distanceMeters: 0,
        riskScore: 0,
        appCheckState: "VERIFIED",
      },
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const evidence = await fraudEvidenceForOrder(orderId);
  // Real App Check state: this raw-HTTP test harness never sends a real
  // App Check token, so the true value is "MISSING" — proving the forged
  // "VERIFIED" was never honored.
  assert.strictEqual(evidence?.interpretation?.appCheckState, "MISSING");
  assert.strictEqual(evidence?.interpretation?.policyVersion, "fraud-f2-signals-only-no-risk-policy");
  // Real computed distance between the address (41.05,29.01) and the
  // candidate (41.06,29.02) is nonzero, never the forged 0.
  assert.notStrictEqual(evidence?.interpretation?.distanceMeters, 0);
  assert.ok((evidence?.interpretation?.distanceMeters as number) > 0);
});

test("FRAUD-F.2: the addressSave evidence remains byte-unchanged after a linked order-submit evidence is created", async () => {
  const fixture = await seedFullValidFixture();
  const priorId = nextId("prior-evidence-2");
  const priorContent = {
    id: priorId, kind: "addressSave", subjectUid: fixture.uid, savedAddressId: fixture.savedAddressId,
    organizationId: null, branchId: null, orderId: null,
    availability: "available",
    clientLocation: {
      latitude: 41.05, longitude: 29.01, accuracyMeters: 10,
      clientCapturedAt: "2026-08-15T09:00:00.000Z", mockLocationStatus: "notDetected",
      permissionState: "granted", precisionState: "precise",
    },
    unavailableReason: null,
    serverReceivedAt: "2026-08-15T09:00:01.000Z", createdAt: "2026-08-15T09:00:02.000Z", expiresAt: null,
    interpretation: { policyVersion: "fraud-f1-signals-only-no-risk-policy" },
  };
  await db().collection("fraudEvidence").doc(priorId).set(priorContent);

  await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );

  const priorAfter = await db().collection("fraudEvidence").doc(priorId).get();
  assert.deepStrictEqual(priorAfter.data(), priorContent);
});

test("FRAUD-F.2: an immutable, versioned FraudRiskContext is created referencing the order-submit evidence", async () => {
  const fixture = await seedFullValidFixture();
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
    }),
    fixture.idToken,
  );
  const orderId = body.result?.orderId as string;
  const riskContext = await riskContextForOrder(orderId);
  assert.strictEqual(riskContext?.orderId, orderId);
  assert.deepStrictEqual(riskContext?.evidenceIds, [`${orderId}-order-submit-evidence`]);
  assert.strictEqual(riskContext?.policyVersion, "fraud-f2-signals-only-no-risk-policy");
});

test("FRAUD-F.2: a large device-location distance alone does NOT reject the order — it is recorded as a signal only", async () => {
  const fixture = await seedFullValidFixture();
  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }],
      deviceLocationCandidate: {
        status: "available",
        latitude: 39.925, // ~Ankara — hundreds of km from the Istanbul address
        longitude: 32.836,
        accuracyMeters: 20,
        clientCapturedAt: "2026-08-16T10:00:00.000Z",
        mockLocationStatus: "notDetected",
        permissionState: "granted",
        precisionState: "precise",
      },
    }),
    fixture.idToken,
  );
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.error, undefined);
  const orderId = body.result?.orderId as string;
  const evidence = await fraudEvidenceForOrder(orderId);
  assert.ok((evidence?.interpretation?.distanceMeters as number) > 300000); // hundreds of km, recorded honestly
});

// =======================================================================
// checkDeliveryEligibility (advisory only)
// =======================================================================

test("checkDeliveryEligibility: an unauthenticated caller is rejected", async () => {
  const { body } = await callCallable(ELIGIBILITY_URL, { savedAddressId: "x" });
  assert.strictEqual(body.error?.status, "UNAUTHENTICATED");
});

test("checkDeliveryEligibility: reports eligible=true with the real minimum for a covered, verified address", async () => {
  const fixture = await seedFullValidFixture({ minimumOrderMinorUnits: 25000 });
  const { body } = await callCallable(ELIGIBILITY_URL, { savedAddressId: fixture.savedAddressId }, fixture.idToken);
  assert.strictEqual(body.result?.eligible, true);
  assert.strictEqual(body.result?.minimumOrderMinorUnits, 25000);
});

test("checkDeliveryEligibility: an eligible result here is advisory only — submitDeliveryOrder still independently re-validates and can reject", async () => {
  const fixture = await seedFullValidFixture({ minimumOrderMinorUnits: 25000 });
  const eligibility = await callCallable(ELIGIBILITY_URL, { savedAddressId: fixture.savedAddressId }, fixture.idToken);
  assert.strictEqual(eligibility.body.result?.eligible, true);

  // A submission below the real minimum is still rejected by
  // submitDeliveryOrder, regardless of the earlier "eligible" advisory
  // result — proving the advisory check is never treated as authorization.
  const { body } = await callCallable(
    SUBMIT_URL,
    validSubmission({
      savedAddressId: fixture.savedAddressId,
      items: [{ kind: "product", productId: fixture.standardProductId, quantity: 1 }], // 24000 < 25000
    }),
    fixture.idToken,
  );
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
});
