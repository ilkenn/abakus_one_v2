import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import {
  runReservationResponseTimeoutSweep,
  runReservationProposalExpirySweep,
} from "../reservationSweep";
import { computePreorderKitchenTiming } from "../reservationPreorder";
import { PREORDER_KITCHEN_RELEASE_LEAD_MINUTES } from "../reservationConfig";

/**
 * Emulator-backed tests for the optional reservation preorder — Faz
 * R.1D.1 (`docs/decisions.md` ADR-027 Faz R.1D.1 design). Covers all 38
 * numbered scenarios from that phase's own spec. Two scenarios live
 * elsewhere by design, not duplicated here:
 *
 * - Test 37 (KDS compatibility) is a Dart-side unit test —
 *   `test/features/pos/domain/kitchen/kitchen_ticket_mapper_test.dart` —
 *   since `KitchenTicketMapper` is Dart code with no TypeScript mirror.
 *   Test 36 (KDS never exposes a pendingConfirmation preorder) is a
 *   structural fact documented in that same file's own comment, not a
 *   runtime assertion (there is no code path today, for any channel, that
 *   invokes KDS mapping automatically).
 * - Test 38 (existing dine-in/takeaway order tests remain green) is proven
 *   by the full suite run itself (`submitTakeawayOrder.test.ts`,
 *   `submitTakeawayOrderRealCatalog.test.ts`, etc. all still passing), not
 *   a new test — writing a redundant copy of that existing coverage here
 *   would just be duplication.
 *
 * The exact `>60m stays pendingConfirmation` / `<=60m confirms immediately`
 * / `kitchenReleaseAt = confirmedTime - 60m` boundary (tests 22/24) is
 * proven twice: once as a pure-function unit test against
 * `computePreorderKitchenTiming` directly (mathematically exact, zero
 * timing risk), and once end-to-end through `respondToReservation`/
 * `respondToProposedChange` using safe margins (mirrors every existing
 * boundary test in this codebase's own reservation suite — see
 * `submitReservation.test.ts`'s own `alignedFutureIso` doc comment for the
 * identical reasoning).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SUBMIT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/submitReservation`;
const RESPOND_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/respondToReservation`;
const ACCEPT_REJECT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/respondToProposedChange`;

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

async function signUpAnonymously(): Promise<{ idToken: string; refreshToken: string; uid: string }> {
  const response = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ returnSecureToken: true }) },
  );
  const body = (await response.json()) as { idToken: string; refreshToken: string; localId: string };
  assert.strictEqual(response.status, 200, "Auth emulator sign-up must succeed");
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}

async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  const body = (await response.json()) as { id_token: string };
  assert.strictEqual(response.status, 200, "Auth emulator token refresh must succeed");
  return body.id_token;
}

async function mintStaffIdToken(organizationId: string, roles: string[]): Promise<string> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, {
    organizationAccess: [organizationId],
    roles: { [organizationId]: roles },
  });
  return refreshIdToken(refreshToken);
}

// Faz R.1C.1.1 — TEST_RUN_ID/PHONE_NAMESPACE make every generated id/phone
// number globally unique across the whole `node --test` invocation, not
// just within this file — mandatory per that phase's own REQUIRED fix.
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

async function seedOrganization(id: string) {
  await admin.firestore().collection("organizations").doc(id).set({ name: "Test Org", isActive: true });
}
async function seedRestaurant(id: string, organizationId: string) {
  await admin.firestore().collection("restaurants").doc(id).set({ organizationId, name: "Test Restaurant", isActive: true });
}
async function seedBranch(id: string, restaurantId: string, organizationId: string) {
  await admin.firestore().collection("branches").doc(id).set({
    restaurantId,
    organizationId,
    name: "Merkez Şube",
    status: "active",
    emergencyStopped: false,
  });
}

interface ReservationPolicyOverrides {
  enabled?: boolean;
  bookingHorizonDays?: number;
  slotIntervalMinutes?: number;
  reservationDurationMinutes?: number;
  maxPartySize?: number;
  customerCancellationCutoffMinutes?: number;
  restaurantResponseTimeoutMinutes?: number;
  proposalHoldMinutes?: number;
  timezone?: string;
}

async function seedReservationPolicy(branchId: string, overrides: ReservationPolicyOverrides = {}) {
  await admin.firestore().collection("reservationPolicies").doc(branchId).set({
    enabled: true,
    bookingHorizonDays: 60,
    slotIntervalMinutes: 15,
    reservationDurationMinutes: 90,
    maxPartySize: 12,
    customerCancellationCutoffMinutes: 60,
    restaurantResponseTimeoutMinutes: 120,
    proposalHoldMinutes: 15,
    timezone: "Europe/Istanbul",
    ...overrides,
  });
}

async function seedReservationArea(
  areaId: string,
  branchId: string,
  overrides: Partial<{ isActive: boolean; capacity: number }> = {},
) {
  await admin.firestore().collection("reservationAreas").doc(areaId).set({
    branchId,
    displayName: "Test Area",
    isActive: true,
    capacity: 10,
    ...overrides,
  });
}

/** Faz R.2 — submitReservation now authoritatively checks branch operating hours; every pre-existing test needs a permissive (all-day, every-day) schedule so this new check never blocks it. */
async function seedWideOpenBranchOperatingHours(branchId: string) {
  const allDay = [{ startMinute: 0, endMinute: 1440 }];
  await admin.firestore().collection("branchOperatingHours").doc(branchId).set({
    branchId,
    weeklySchedule: {
      monday: allDay, tuesday: allDay, wednesday: allDay, thursday: allDay,
      friday: allDay, saturday: allDay, sunday: allDay,
    },
    dateOverrides: {},
  });
}
async function seedValidReservationChain(
  policyOverrides: ReservationPolicyOverrides = {},
  areaOverrides: Partial<{ isActive: boolean; capacity: number }> = {},
) {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedReservationPolicy(branchId, policyOverrides);
  await seedReservationArea(areaId, branchId, areaOverrides);
  await seedWideOpenBranchOperatingHours(branchId);
  return { organizationId, restaurantId, branchId, areaId };
}

async function seedChannelPricingPolicy(
  restaurantId: string,
  policy: { channelDefaultAdjustments?: Record<string, number>; categoryOverrides?: Record<string, Record<string, number>> },
) {
  await admin.firestore().collection("channelPricingPolicies").doc(restaurantId).set({
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

async function seedMenuProduct(id: string, restaurantId: string, organizationId: string, overrides: SeedProductOverrides = {}) {
  await admin.firestore().collection("menuProducts").doc(id).set({
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
  await admin.firestore().collection("bowlIngredients").doc(id).set({
    organizationId,
    restaurantId,
    categoryId: overrides.categoryId ?? "protein",
    name: "Test Ingredient",
    priceMinorUnits: overrides.priceMinorUnits ?? 5000,
    isAvailable: overrides.isAvailable ?? true,
  });
}

/** Floored to the current 15-minute slot boundary — see submitReservation.test.ts's own identical helper for the full margin reasoning. */
function alignedFutureIso(minutesFromNow: number, referenceNow: number = Date.now()): string {
  const slotMs = 15 * 60_000;
  const flooredNow = Math.floor(referenceNow / slotMs) * slotMs;
  return new Date(flooredNow + minutesFromNow * 60_000).toISOString();
}

const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz" };

async function getReservation(reservationId: string) {
  const doc = await admin.firestore().collection("reservations").doc(reservationId).get();
  return doc.data()!;
}
async function getOrder(orderId: string) {
  const doc = await admin.firestore().collection("orders").doc(orderId).get();
  return doc.data();
}

/** A full, valid chain plus one available product and one available bowl ingredient — the standard fixture most preorder tests start from. */
async function seedPreorderFixture() {
  const chain = await seedValidReservationChain();
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  const ingredientId = nextId("ingredient");
  await seedBowlIngredient(ingredientId, chain.restaurantId, chain.organizationId, { priceMinorUnits: 3000 });
  return { ...chain, productId, ingredientId };
}

// =======================================================================
// 1. Reservation without preorder still works unchanged
// =======================================================================

test("1. reservation without a preorder field behaves exactly as before — no order created, preorderOrderId null", async () => {
  const chain = await seedValidReservationChain();
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 200, JSON.stringify(body));
  assert.strictEqual(body.result?.preorderOrderId, null);
  const reservation = await getReservation(body.result!.reservationId as string);
  assert.strictEqual(reservation.preorderOrderId, null);
});

// =======================================================================
// 2/6/7/8. Identity
// =======================================================================

test("2. preorder requires real phone-auth through the reservation flow — anonymous rejected", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: fixture.restaurantId,
      branchId: fixture.branchId,
      areaId: fixture.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
      preorder: { items: [{ kind: "product", productId: fixture.productId, quantity: 1 }] },
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("6. customerId on the preorder order equals the phone-auth uid", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken, uid } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: fixture.restaurantId,
      branchId: fixture.branchId,
      areaId: fixture.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
      preorder: { items: [{ kind: "product", productId: fixture.productId, quantity: 1 }] },
    },
    idToken,
  );

  const order = await getOrder(body.result!.preorderOrderId as string);
  assert.strictEqual(order!.customerId, uid);
});

test("7/8. no fake tableSessionId or guestAuthUid on a preorder order", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: fixture.restaurantId,
      branchId: fixture.branchId,
      areaId: fixture.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
      preorder: { items: [{ kind: "product", productId: fixture.productId, quantity: 1 }] },
    },
    idToken,
  );

  const order = await getOrder(body.result!.preorderOrderId as string);
  assert.strictEqual(order!.tableSessionId, null);
  assert.strictEqual(order!.guestAuthUid, null);
  assert.strictEqual(order!.tableId, null);
});

// =======================================================================
// 3/4/5. Separate Order aggregate, channel, linkage
// =======================================================================

test("3/4/5. preorder creates a separate Order — channel reservationPreorder, reservationContextId == reservationId, distinct id from the reservation", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: fixture.restaurantId,
      branchId: fixture.branchId,
      areaId: fixture.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
      preorder: { items: [{ kind: "product", productId: fixture.productId, quantity: 1 }] },
    },
    idToken,
  );

  const reservationId = body.result!.reservationId as string;
  const preorderOrderId = body.result!.preorderOrderId as string;
  assert.notStrictEqual(preorderOrderId, reservationId);

  const order = await getOrder(preorderOrderId);
  assert.ok(order, "the preorder order must exist");
  assert.strictEqual(order!.channel, "reservationPreorder");
  assert.strictEqual(order!.reservationContextId, reservationId);
  // Boncuk Loyalty P2A security fix (2026-08-21) — the exact canonical
  // server pricing-authority marker, stamped by this server pipeline.
  assert.strictEqual(order!.pricingAuthority, "serverV1");

  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.preorderOrderId, preorderOrderId);
});

test("pricingAuthority cannot originate from the request payload — a request-payload override attempt is ignored", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: fixture.restaurantId,
      branchId: fixture.branchId,
      areaId: fixture.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
      preorder: {
        items: [{ kind: "product", productId: fixture.productId, quantity: 1 }],
        pricingAuthority: "client-forged-value",
      },
    },
    idToken,
  );

  const preorderOrderId = body.result!.preorderOrderId as string;
  const order = await getOrder(preorderOrderId);
  assert.strictEqual(order!.pricingAuthority, "serverV1");
});

// =======================================================================
// 9-15. Server-authoritative pricing
// =======================================================================

test("9/10. server canonical product price is used; a forged client price field has no effect", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: fixture.restaurantId,
      branchId: fixture.branchId,
      areaId: fixture.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
      preorder: {
        items: [
          // unitPrice/price are not part of the accepted item shape at
          // all — a forged value here has nothing to be read into.
          { kind: "product", productId: fixture.productId, quantity: 1, unitPrice: 1, price: 999999 },
        ],
      },
    },
    idToken,
  );

  const order = await getOrder(body.result!.preorderOrderId as string);
  assert.strictEqual(order!.pricing.grandTotal.minorUnits, 10000);
  assert.strictEqual(order!.lines[0].unitPrice.minorUnits, 10000);
});

test("11/12. Gel Al packaging surcharge and delivery surcharge are never applied to a preorder, even when both are configured on the same restaurant's policy", async () => {
  const fixture = await seedPreorderFixture();
  await seedChannelPricingPolicy(fixture.restaurantId, {
    channelDefaultAdjustments: { takeaway: 2000, delivery: 1500 },
  });
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: fixture.restaurantId,
      branchId: fixture.branchId,
      areaId: fixture.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
      preorder: { items: [{ kind: "product", productId: fixture.productId, quantity: 1 }] },
    },
    idToken,
  );

  const order = await getOrder(body.result!.preorderOrderId as string);
  assert.strictEqual(order!.pricing.grandTotal.minorUnits, 10000, "table/base price only — no takeaway/delivery adjustment leaked in");
  assert.strictEqual(order!.pricing.packagingFee.minorUnits, 0);
  assert.strictEqual(order!.pricing.deliveryFee.minorUnits, 0);
});

test("13. bowl canonical pricing — ingredient total plus zero channel adjustment", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: fixture.restaurantId,
      branchId: fixture.branchId,
      areaId: fixture.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
      preorder: { items: [{ kind: "bowl", quantity: 1, ingredientIds: [fixture.ingredientId] }] },
    },
    idToken,
  );

  const order = await getOrder(body.result!.preorderOrderId as string);
  assert.strictEqual(order!.lines[0].unitPrice.minorUnits, 0, "bowl channel adjustment for reservationPreorder is unconfigured, hence zero");
  assert.strictEqual(order!.pricing.grandTotal.minorUnits, 3000, "ingredient total only");
});

test("14. an inactive product is rejected fail-closed", async () => {
  const fixture = await seedPreorderFixture();
  await admin.firestore().collection("menuProducts").doc(fixture.productId).update({ isAvailable: false });
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: fixture.restaurantId,
      branchId: fixture.branchId,
      areaId: fixture.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
      preorder: { items: [{ kind: "product", productId: fixture.productId, quantity: 1 }] },
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("15. an invalid modifier selection is rejected", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: fixture.restaurantId,
      branchId: fixture.branchId,
      areaId: fixture.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
      preorder: {
        items: [
          {
            kind: "product",
            productId: fixture.productId,
            quantity: 1,
            selectedModifiers: [{ groupId: "nonexistent-group", optionId: "nonexistent-option" }],
          },
        ],
      },
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

// =======================================================================
// 16-18. Atomicity / idempotency
// =======================================================================

test("16. a rejected preorder line rolls back the whole transaction — no Reservation, no hold, no order", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();
  const submissionKey = nextId("key");

  const { httpStatus } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey,
      restaurantId: fixture.restaurantId,
      branchId: fixture.branchId,
      areaId: fixture.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
      preorder: { items: [{ kind: "product", productId: "does-not-exist", quantity: 1 }] },
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  const reservationsSnapshot = await admin
    .firestore()
    .collection("reservations")
    .where("branchId", "==", fixture.branchId)
    .get();
  assert.strictEqual(reservationsSnapshot.empty, true, "no partial Reservation may exist after a failed preorder");
  const holdsSnapshot = await admin
    .firestore()
    .collection("reservationHolds")
    .where("branchId", "==", fixture.branchId)
    .get();
  assert.strictEqual(holdsSnapshot.empty, true, "no partial hold may exist after a failed preorder");
});

test("17. duplicate submit (same submissionKey, same preorder) creates exactly one Reservation and one Order", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();
  const payload = {
    submissionKey: nextId("key"),
    restaurantId: fixture.restaurantId,
    branchId: fixture.branchId,
    areaId: fixture.areaId,
    partySize: 2,
    requestedTime: alignedFutureIso(90),
    ...CONTACT,
    preorder: { items: [{ kind: "product", productId: fixture.productId, quantity: 1 }] },
  };

  const first = await callCallable(SUBMIT_URL, payload, idToken);
  const second = await callCallable(SUBMIT_URL, payload, idToken);

  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.duplicate, true);
  assert.strictEqual(second.body.result?.reservationId, first.body.result?.reservationId);
  assert.strictEqual(second.body.result?.preorderOrderId, first.body.result?.preorderOrderId);

  const ordersSnapshot = await admin
    .firestore()
    .collection("orders")
    .where("reservationContextId", "==", first.body.result!.reservationId as string)
    .get();
  assert.strictEqual(ordersSnapshot.size, 1, "exactly one Order for this reservation, never duplicated");
});

test("18. a full-slot-at-submission reservation still creates its preorder", async () => {
  const chain = await seedValidReservationChain({}, { capacity: 2 });
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  const requestedTime = alignedFutureIso(90);

  const userA = await createRealPhoneUser();
  const fillIt = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime,
      ...CONTACT,
    },
    userA.idToken,
  );
  assert.strictEqual(fillIt.body.result?.requestedAvailabilityAtSubmission, "available");

  const userB = await createRealPhoneUser();
  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime,
      ...CONTACT,
      preorder: { items: [{ kind: "product", productId, quantity: 1 }] },
    },
    userB.idToken,
  );

  assert.strictEqual(body.result?.requestedAvailabilityAtSubmission, "unavailable");
  assert.ok(body.result?.preorderOrderId, "a preorder must still be created even though the slot was full");
  const order = await getOrder(body.result!.preorderOrderId as string);
  assert.ok(order);
  assert.strictEqual(order!.status, "pendingConfirmation");
});

// =======================================================================
// 19/20. Initial preorder state
// =======================================================================

test("19/20. preorder starts pendingConfirmation with kitchenReleaseAt null", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: fixture.restaurantId,
      branchId: fixture.branchId,
      areaId: fixture.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
      preorder: { items: [{ kind: "product", productId: fixture.productId, quantity: 1 }] },
    },
    idToken,
  );

  const order = await getOrder(body.result!.preorderOrderId as string);
  assert.strictEqual(order!.status, "pendingConfirmation");
  assert.strictEqual(order!.kitchenReleaseAt, null);
});

// =======================================================================
// 21-24. Direct confirm timing (respondToReservation confirm)
// =======================================================================

async function submitWithPreorder(fixture: { restaurantId: string; branchId: string; areaId: string; productId: string }, requestedTime: string, idToken: string) {
  return callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: fixture.restaurantId,
      branchId: fixture.branchId,
      areaId: fixture.areaId,
      partySize: 2,
      requestedTime,
      ...CONTACT,
      preorder: { items: [{ kind: "product", productId: fixture.productId, quantity: 1 }] },
    },
    idToken,
  );
}

test("21. direct confirm with >60m remaining: preorder stays pendingConfirmation, kitchenReleaseAt = requestedTime - 60m", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();
  const requestedTime = alignedFutureIso(90); // safely >60m even after floor/latency
  const submitted = await submitWithPreorder(fixture, requestedTime, idToken);
  const reservationId = submitted.body.result!.reservationId as string;
  const preorderOrderId = submitted.body.result!.preorderOrderId as string;

  const staffToken = await mintStaffIdToken(fixture.organizationId, ["manager"]);
  const { httpStatus } = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, staffToken);
  assert.strictEqual(httpStatus, 200);

  const order = await getOrder(preorderOrderId);
  assert.strictEqual(order!.status, "pendingConfirmation");
  const expectedReleaseAt = new Date(
    new Date(requestedTime).getTime() - PREORDER_KITCHEN_RELEASE_LEAD_MINUTES * 60_000,
  ).toISOString();
  assert.strictEqual(order!.kitchenReleaseAt, expectedReleaseAt);
});

test("22/23. direct confirm at-or-under the 60m lead time: preorder is immediately confirmed", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();
  const requestedTime = alignedFutureIso(45); // >=30m minimum-advance-safe, comfortably <60m lead
  const submitted = await submitWithPreorder(fixture, requestedTime, idToken);
  const reservationId = submitted.body.result!.reservationId as string;
  const preorderOrderId = submitted.body.result!.preorderOrderId as string;

  const staffToken = await mintStaffIdToken(fixture.organizationId, ["manager"]);
  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, staffToken);

  const order = await getOrder(preorderOrderId);
  assert.strictEqual(order!.status, "confirmed");
  assert.ok(order!.kitchenReleaseAt);
  assert.ok(order!.timestamps.confirmed, "timestamps.confirmed must be set on the pendingConfirmation -> confirmed transition");
});

test("24. computePreorderKitchenTiming — exact boundary, mathematically precise (pure function)", () => {
  const confirmedTime = new Date("2026-01-01T12:00:00.000Z");
  const leadMs = PREORDER_KITCHEN_RELEASE_LEAD_MINUTES * 60_000;

  const justOver = computePreorderKitchenTiming(confirmedTime, new Date(confirmedTime.getTime() - leadMs - 1));
  assert.strictEqual(justOver.status, "pendingConfirmation");

  const exactlyAtBoundary = computePreorderKitchenTiming(confirmedTime, new Date(confirmedTime.getTime() - leadMs));
  assert.strictEqual(exactlyAtBoundary.status, "confirmed", "remaining === lead is inclusive -> confirmed");

  const justUnder = computePreorderKitchenTiming(confirmedTime, new Date(confirmedTime.getTime() - leadMs + 1));
  assert.strictEqual(justUnder.status, "confirmed");

  assert.strictEqual(
    exactlyAtBoundary.kitchenReleaseAt.getTime(),
    confirmedTime.getTime() - leadMs,
    "kitchenReleaseAt = confirmedTime - lead, always",
  );
});

// =======================================================================
// 25/26. Proposal accept timing
// =======================================================================

test("25. proposal accept with >60m remaining recalculates kitchenReleaseAt, preorder stays pendingConfirmation", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();
  // 90 (a multiple of the default 15-minute slot) — not 50, which isn't
  // slot-aligned and would fail submitReservation's own alignment check.
  const submitted = await submitWithPreorder(fixture, alignedFutureIso(90), idToken);
  const reservationId = submitted.body.result!.reservationId as string;
  const preorderOrderId = submitted.body.result!.preorderOrderId as string;

  const staffToken = await mintStaffIdToken(fixture.organizationId, ["manager"]);
  const proposedTime = alignedFutureIso(120); // >60m
  const propose = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime, proposedAreaId: fixture.areaId },
    staffToken,
  );
  const proposalId = propose.body.result!.proposalId as string;

  await callCallable(ACCEPT_REJECT_URL, { reservationId, proposalId, action: "accept" }, idToken);

  const order = await getOrder(preorderOrderId);
  assert.strictEqual(order!.status, "pendingConfirmation");
  const expectedReleaseAt = new Date(
    new Date(proposedTime).getTime() - PREORDER_KITCHEN_RELEASE_LEAD_MINUTES * 60_000,
  ).toISOString();
  assert.strictEqual(order!.kitchenReleaseAt, expectedReleaseAt);
});

test("26. proposal accept with <=60m remaining confirms the preorder immediately", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();
  const submitted = await submitWithPreorder(fixture, alignedFutureIso(120), idToken);
  const reservationId = submitted.body.result!.reservationId as string;
  const preorderOrderId = submitted.body.result!.preorderOrderId as string;

  const staffToken = await mintStaffIdToken(fixture.organizationId, ["manager"]);
  const proposedTime = alignedFutureIso(45); // <60m
  const propose = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime, proposedAreaId: fixture.areaId },
    staffToken,
  );
  const proposalId = propose.body.result!.proposalId as string;

  await callCallable(ACCEPT_REJECT_URL, { reservationId, proposalId, action: "accept" }, idToken);

  const order = await getOrder(preorderOrderId);
  assert.strictEqual(order!.status, "confirmed");
});

// =======================================================================
// 27/28. Proposal reject / expiry leave the preorder untouched
// =======================================================================

test("27. proposal reject leaves the preorder pendingConfirmation, kitchenReleaseAt still null", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();
  const submitted = await submitWithPreorder(fixture, alignedFutureIso(90), idToken);
  const reservationId = submitted.body.result!.reservationId as string;
  const preorderOrderId = submitted.body.result!.preorderOrderId as string;

  const staffToken = await mintStaffIdToken(fixture.organizationId, ["manager"]);
  const propose = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime: alignedFutureIso(120), proposedAreaId: fixture.areaId },
    staffToken,
  );
  const proposalId = propose.body.result!.proposalId as string;

  await callCallable(ACCEPT_REJECT_URL, { reservationId, proposalId, action: "reject" }, idToken);

  const order = await getOrder(preorderOrderId);
  assert.strictEqual(order!.status, "pendingConfirmation");
  assert.strictEqual(order!.kitchenReleaseAt, null);
});

test("28. proposal expiry leaves the preorder pendingConfirmation, kitchenReleaseAt still null", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();
  const submitted = await submitWithPreorder(fixture, alignedFutureIso(90), idToken);
  const reservationId = submitted.body.result!.reservationId as string;
  const preorderOrderId = submitted.body.result!.preorderOrderId as string;

  const staffToken = await mintStaffIdToken(fixture.organizationId, ["manager"]);
  const propose = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime: alignedFutureIso(120), proposedAreaId: fixture.areaId },
    staffToken,
  );
  const proposalId = propose.body.result!.proposalId as string;

  const sweepNow = new Date(Date.now() + 60 * 60_000);
  const processed = await runReservationProposalExpirySweep(admin.firestore(), sweepNow);
  assert.ok(processed >= 1);

  const proposalDoc = await admin.firestore().collection("reservationChangeProposals").doc(proposalId).get();
  assert.strictEqual(proposalDoc.data()!.status, "expired");

  const order = await getOrder(preorderOrderId);
  assert.strictEqual(order!.status, "pendingConfirmation");
  assert.strictEqual(order!.kitchenReleaseAt, null);
});

// =======================================================================
// 29/30. Restaurant reject / response timeout cancel the preorder
// =======================================================================

test("29. restaurant reject cancels the linked preorder in the same transaction", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();
  const submitted = await submitWithPreorder(fixture, alignedFutureIso(90), idToken);
  const reservationId = submitted.body.result!.reservationId as string;
  const preorderOrderId = submitted.body.result!.preorderOrderId as string;

  const staffToken = await mintStaffIdToken(fixture.organizationId, ["manager"]);
  const { httpStatus } = await callCallable(
    RESPOND_URL,
    { reservationId, action: "reject", reasonCode: "fullyBooked" },
    staffToken,
  );
  assert.strictEqual(httpStatus, 200);

  const order = await getOrder(preorderOrderId);
  assert.strictEqual(order!.status, "cancelled");
  assert.strictEqual(order!.kitchenReleaseAt, null);
});

test("30. response-timeout sweep cancels the linked preorder", async () => {
  const chain = await seedValidReservationChain({ restaurantResponseTimeoutMinutes: 1 });
  const productId = nextId("product");
  await seedMenuProduct(productId, chain.restaurantId, chain.organizationId, { basePriceMinorUnits: 10000 });
  const { idToken } = await createRealPhoneUser();

  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
      preorder: { items: [{ kind: "product", productId, quantity: 1 }] },
    },
    idToken,
  );
  const preorderOrderId = body.result!.preorderOrderId as string;

  const sweepNow = new Date(Date.now() + 5 * 60_000);
  const processed = await runReservationResponseTimeoutSweep(admin.firestore(), sweepNow);
  assert.ok(processed >= 1);

  const order = await getOrder(preorderOrderId);
  assert.strictEqual(order!.status, "cancelled");
  assert.strictEqual(order!.kitchenReleaseAt, null);
});

// =======================================================================
// 31/32. Duplicate confirm/reject/timeout retries are safe
// =======================================================================

test("31. duplicate confirm cannot transition the preorder twice", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();
  const submitted = await submitWithPreorder(fixture, alignedFutureIso(45), idToken);
  const reservationId = submitted.body.result!.reservationId as string;
  const preorderOrderId = submitted.body.result!.preorderOrderId as string;

  const staffToken = await mintStaffIdToken(fixture.organizationId, ["manager"]);
  await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, staffToken);
  const orderAfterFirst = await getOrder(preorderOrderId);

  const second = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, staffToken);
  assert.strictEqual(second.body.result?.duplicate, true);

  const orderAfterSecond = await getOrder(preorderOrderId);
  assert.strictEqual(orderAfterSecond!.version, orderAfterFirst!.version, "a duplicate confirm must never re-transition or re-version the preorder");
  const confirmedEntries = (orderAfterSecond!.statusHistory as { newValue: string }[]).filter(
    (e) => e.newValue === "confirmed",
  );
  assert.strictEqual(confirmedEntries.length, 1, "exactly one confirmed transition, never duplicated");
});

test("32. duplicate reject and repeated timeout-sweep retries are safe", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();
  const submitted = await submitWithPreorder(fixture, alignedFutureIso(90), idToken);
  const reservationId = submitted.body.result!.reservationId as string;
  const preorderOrderId = submitted.body.result!.preorderOrderId as string;

  const staffToken = await mintStaffIdToken(fixture.organizationId, ["manager"]);
  await callCallable(RESPOND_URL, { reservationId, action: "reject", reasonCode: "fullyBooked" }, staffToken);
  const orderAfterFirst = await getOrder(preorderOrderId);

  const second = await callCallable(
    RESPOND_URL,
    { reservationId, action: "reject", reasonCode: "fullyBooked" },
    staffToken,
  );
  assert.strictEqual(second.body.result?.duplicate, true);

  const orderAfterSecond = await getOrder(preorderOrderId);
  assert.strictEqual(orderAfterSecond!.version, orderAfterFirst!.version);
  const cancelledEntries = (orderAfterSecond!.statusHistory as { newValue: string }[]).filter(
    (e) => e.newValue === "cancelled",
  );
  assert.strictEqual(cancelledEntries.length, 1);
});

// =======================================================================
// 33. Reservation-only response workflows unchanged
// =======================================================================

test("33. confirm/reject on a reservation with no preorder is unaffected — no order ever created or referenced", async () => {
  const chain = await seedValidReservationChain();
  const { idToken } = await createRealPhoneUser();

  const submitted = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
    },
    idToken,
  );
  const reservationId = submitted.body.result!.reservationId as string;

  const staffToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { httpStatus, body } = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, staffToken);

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.status, "confirmed");
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.preorderOrderId, null);
});

// =======================================================================
// 34/35. Security
// =======================================================================

test("34. a preorder item referencing another tenant's product is rejected — cross-tenant catalog access fails closed", async () => {
  const fixtureA = await seedPreorderFixture();
  const fixtureB = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: fixtureA.restaurantId,
      branchId: fixtureA.branchId,
      areaId: fixtureA.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
      // fixtureB's product does not belong to fixtureA's restaurant.
      preorder: { items: [{ kind: "product", productId: fixtureB.productId, quantity: 1 }] },
    },
    idToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "INVALID_ARGUMENT");
});

test("35. respondToReservation/respondToProposedChange never accept a client-supplied order id — only reservation/proposal ids are read from the request", async () => {
  const fixture = await seedPreorderFixture();
  const { idToken } = await createRealPhoneUser();
  // 45m (<60m lead) so a successful confirm deterministically flips this
  // preorder to "confirmed" — the clearest possible proof the REAL linked
  // order was actually resolved and mutated, not the forged one.
  const submitted = await submitWithPreorder(fixture, alignedFutureIso(45), idToken);
  const reservationId = submitted.body.result!.reservationId as string;
  const realPreorderOrderId = submitted.body.result!.preorderOrderId as string;

  // A forged orderId in the payload — respondToReservation's request shape
  // has no such field at all, so there is nothing for a forged value to
  // influence; the linked preorder is still resolved purely from the
  // reservation's own stored preorderOrderId.
  const staffToken = await mintStaffIdToken(fixture.organizationId, ["manager"]);
  await callCallable(
    RESPOND_URL,
    { reservationId, action: "confirm", orderId: "attacker-supplied-order-id", preorderOrderId: "attacker-supplied-order-id" },
    staffToken,
  );

  const realOrder = await getOrder(realPreorderOrderId);
  assert.strictEqual(realOrder!.status, "confirmed", "the REAL linked preorder was resolved and transitioned, ignoring the forged field");
  const forgedOrder = await getOrder("attacker-supplied-order-id");
  assert.strictEqual(forgedOrder, undefined, "no document was ever created/touched at the forged id");
});
