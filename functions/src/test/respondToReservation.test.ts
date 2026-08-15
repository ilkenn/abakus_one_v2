import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `respondToReservation` — Faz R.1B
 * (`docs/decisions.md` ADR-027 Faz R.1B design). Mirrors
 * `submitReservation.test.ts`/`provisioning.test.ts`'s exact pattern: raw
 * HTTP against the callable-functions wire protocol, real Firestore
 * fixtures seeded directly via the Admin SDK, staff identities minted via
 * `provisioning.test.ts`'s own anonymous-sign-up + `setCustomUserClaims` +
 * refresh-token dance (`organizationAccess`/`roles` claims, never
 * `platformRole` — a wholly separate namespace).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SUBMIT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/submitReservation`;
const RESPOND_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/respondToReservation`;

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

/** Faz R.1B's own manager-tier convention (`manager`/`admin`/`tenantOwner`) — mirrors `provisioning.test.ts`'s `mintTenantAdminIdToken` shape. */
async function mintStaffIdToken(organizationId: string, roles: string[]): Promise<string> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, {
    organizationAccess: [organizationId],
    roles: { [organizationId]: roles },
  });
  return refreshIdToken(refreshToken);
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
    restaurantId, organizationId, name: "Merkez Şube", status: "active", emergencyStopped: false,
  });
}
interface PolicyOverrides {
  restaurantResponseTimeoutMinutes?: number;
  proposalHoldMinutes?: number;
  slotIntervalMinutes?: number;
  reservationDurationMinutes?: number;
  bookingHorizonDays?: number;
  maxPartySize?: number;
}
async function seedReservationPolicy(branchId: string, overrides: PolicyOverrides = {}) {
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
async function seedReservationArea(areaId: string, branchId: string, capacity = 10) {
  await admin.firestore().collection("reservationAreas").doc(areaId).set({
    branchId, displayName: "Test Area", isActive: true, capacity,
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
async function seedValidReservationChain(policyOverrides: PolicyOverrides = {}, capacity = 10) {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedReservationPolicy(branchId, policyOverrides);
  await seedReservationArea(areaId, branchId, capacity);
  await seedWideOpenBranchOperatingHours(branchId);
  return { organizationId, restaurantId, branchId, areaId };
}

function alignedFutureIso(minutesFromNow: number, referenceNow: number = Date.now()): string {
  const slotMs = 15 * 60_000;
  const flooredNow = Math.floor(referenceNow / slotMs) * slotMs;
  return new Date(flooredNow + minutesFromNow * 60_000).toISOString();
}

const CONTACT = { contactFirstName: "Ada", contactLastName: "Yılmaz" };

/** Submits a reservation via the real callable and returns its id + response payload. */
async function submitReservationFixture(
  chain: { restaurantId: string; branchId: string; areaId: string },
  overrides: { partySize?: number; requestedTime?: string } = {},
) {
  const { idToken } = await createRealPhoneUser();
  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: overrides.partySize ?? 2,
      requestedTime: overrides.requestedTime ?? alignedFutureIso(60),
      ...CONTACT,
    },
    idToken,
  );
  return { reservationId: body.result!.reservationId as string, result: body.result!, customerIdToken: idToken };
}

async function getReservation(reservationId: string) {
  const doc = await admin.firestore().collection("reservations").doc(reservationId).get();
  return doc.data()!;
}
async function getHold(holdId: string) {
  const doc = await admin.firestore().collection("reservationHolds").doc(holdId).get();
  return doc.data()!;
}
function bucketId(branchId: string, areaId: string, slotStartIso: string): string {
  return `${branchId}__${areaId}__${slotStartIso}`;
}
async function getBucket(id: string) {
  const doc = await admin.firestore().collection("reservationSlotOccupancy").doc(id).get();
  return doc.data();
}
async function getEvent(eventId: string) {
  const doc = await admin.firestore().collection("reservationEvents").doc(eventId).get();
  return doc.exists ? doc.data() : null;
}

// =======================================================================
// A. Authorization (tests 1-2, + Faz R.1B.1 permission-model tests)
// =======================================================================

test("respondToReservation: staff with no manageReservations role (base staff tier) is rejected — permission-denied", async () => {
  const chain = await seedValidReservationChain();
  const { reservationId } = await submitReservationFixture(chain);
  const staffToken = await mintStaffIdToken(chain.organizationId, ["staff"]);

  const { httpStatus, body } = await callCallable(
    RESPOND_URL,
    { reservationId, action: "confirm" },
    staffToken,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "pendingRestaurantApproval");
});

test("respondToReservation: manager from a different tenant is rejected — cross-tenant fails closed", async () => {
  const chain = await seedValidReservationChain();
  const { reservationId } = await submitReservationFixture(chain);
  const otherOrgToken = await mintStaffIdToken(nextId("other-org"), ["manager"]);

  const { httpStatus, body } = await callCallable(
    RESPOND_URL,
    { reservationId, action: "confirm" },
    otherOrgToken,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("respondToReservation: tenantOwner is authorized through the same canonical manageReservations permission resolution as manager — not a separate role-specific path", async () => {
  const chain = await seedValidReservationChain();
  const { reservationId } = await submitReservationFixture(chain);
  const tenantOwnerToken = await mintStaffIdToken(chain.organizationId, ["tenantOwner"]);

  const { httpStatus, body } = await callCallable(
    RESPOND_URL,
    { reservationId, action: "confirm" },
    tenantOwnerToken,
  );

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.status, "confirmed");
});

// =======================================================================
// B. Direct confirm (tests 3-8)
// =======================================================================

test("respondToReservation: manager can confirm a pending reservation with an active hold", async () => {
  const chain = await seedValidReservationChain();
  const { reservationId } = await submitReservationFixture(chain);
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);

  const { httpStatus, body } = await callCallable(
    RESPOND_URL,
    { reservationId, action: "confirm" },
    managerToken,
  );

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.status, "confirmed");
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "confirmed");
  assert.strictEqual(reservation.activeHoldId, null);
  assert.ok(reservation.confirmedTime);
  assert.strictEqual(reservation.confirmedAreaId, chain.areaId);
  // Faz R.1B.1 — the reservationEvent commits atomically with the state
  // transition (same transaction, not a separate post-commit step).
  const event = await getEvent(`${reservationId}-confirmed`);
  assert.ok(event, "reservationConfirmed event must exist immediately after a successful confirm");
  assert.strictEqual(event?.type, "reservationConfirmed");
  assert.strictEqual(event?.reservationId, reservationId);
  assert.strictEqual(event?.delivered, false);
});

test("respondToReservation: confirm consumes the active initial hold exactly once", async () => {
  const chain = await seedValidReservationChain();
  const { reservationId, result } = await submitReservationFixture(chain, { partySize: 3 });
  const reservationBefore = await getReservation(reservationId);
  const holdId = reservationBefore.activeHoldId as string;
  const holdBefore = await getHold(holdId);
  const bId = (holdBefore.bucketIds as string[])[0];
  const bucketBefore = await getBucket(bId);
  assert.strictEqual(bucketBefore?.heldPartySize, 3);
  assert.strictEqual(bucketBefore?.confirmedPartySize, 0);

  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { httpStatus } = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, managerToken);
  assert.strictEqual(httpStatus, 200);
  void result;

  const holdAfter = await getHold(holdId);
  assert.strictEqual(holdAfter.status, "consumed");
  const bucketAfter = await getBucket(bId);
  assert.strictEqual(bucketAfter?.heldPartySize, 0);
  assert.strictEqual(bucketAfter?.confirmedPartySize, 3);
});

test("respondToReservation: duplicate confirm (retry) is safe — does not double-increment confirmedPartySize", async () => {
  const chain = await seedValidReservationChain();
  const { reservationId } = await submitReservationFixture(chain, { partySize: 4 });
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);

  const first = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, managerToken);
  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(first.body.result?.duplicate, false);
  const eventAfterFirst = await getEvent(`${reservationId}-confirmed`);
  assert.ok(eventAfterFirst);
  const recordedAtAfterFirst = eventAfterFirst?.recordedAt;

  const second = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, managerToken);
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.status, "confirmed");
  assert.strictEqual(second.body.result?.duplicate, true);

  const reservation = await getReservation(reservationId);
  const bId = bucketId(chain.branchId, chain.areaId, new Date(reservation.requestedTime.toDate()).toISOString());
  const bucket = await getBucket(bId);
  assert.strictEqual(bucket?.confirmedPartySize, 4);
  // Faz R.1B.1 — the duplicate confirm returns early (before reaching
  // writeReservationEvent at all), so the single deterministic-id event
  // document is left completely untouched, not overwritten a second time.
  const eventAfterSecond = await getEvent(`${reservationId}-confirmed`);
  assert.ok(eventAfterSecond);
  assert.strictEqual(eventAfterSecond?.recordedAt, recordedAtAfterFirst, "duplicate confirm must not re-write (or duplicate) the reservationConfirmed event");
});

test("respondToReservation: confirm re-checks current capacity when the initial hold is expired (defensive path — hold.expiresAt manipulated independently of responseDeadlineAt)", async () => {
  const chain = await seedValidReservationChain({ restaurantResponseTimeoutMinutes: 120 });
  const { reservationId } = await submitReservationFixture(chain, { partySize: 2 });
  const reservation = await getReservation(reservationId);
  const holdId = reservation.activeHoldId as string;
  // Directly age the hold's own expiresAt into the past — independent of
  // responseDeadlineAt (still far in the future), exercising confirm's
  // defensive "hold missing/expired/wrong-status -> fresh recheck" branch
  // (Faz R.1B §3) rather than the "responseDeadlineAt passed" branch.
  await admin.firestore().collection("reservationHolds").doc(holdId).set(
    { expiresAt: new Date(Date.now() - 60_000) },
    { merge: true },
  );

  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { httpStatus, body } = await callCallable(RESPOND_URL, { reservationId, action: "confirm" }, managerToken);

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.status, "confirmed");
  const holdAfter = await getHold(holdId);
  // The expired hold is left untouched (never consumed) — capacity was
  // freshly re-claimed instead.
  assert.strictEqual(holdAfter.status, "active");
});

test("respondToReservation: confirm fails with failed-precondition when capacity is unavailable and no usable hold exists", async () => {
  const chain = await seedValidReservationChain({}, 2);
  const requestedTime = alignedFutureIso(60);
  const filler = await submitReservationFixture(chain, { partySize: 2, requestedTime });
  const target = await submitReservationFixture(chain, { partySize: 2, requestedTime });
  assert.strictEqual(target.result.requestedAvailabilityAtSubmission, "unavailable");
  void filler;

  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { httpStatus, body } = await callCallable(
    RESPOND_URL,
    { reservationId: target.reservationId, action: "confirm" },
    managerToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const reservation = await getReservation(target.reservationId);
  assert.strictEqual(reservation.status, "pendingRestaurantApproval");
});

test("respondToReservation: a reservation that was full at submission (no hold created) can still be confirmed later once capacity opens", async () => {
  const chain = await seedValidReservationChain({}, 2);
  const requestedTime = alignedFutureIso(60);
  const filler = await submitReservationFixture(chain, { partySize: 2, requestedTime });
  const target = await submitReservationFixture(chain, { partySize: 2, requestedTime });
  assert.strictEqual(target.result.requestedAvailabilityAtSubmission, "unavailable");
  const targetReservation = await getReservation(target.reservationId);
  assert.strictEqual(targetReservation.activeHoldId, null);

  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  // Free up capacity by rejecting the filler reservation first.
  const rejectFiller = await callCallable(
    RESPOND_URL,
    { reservationId: filler.reservationId, action: "reject" },
    managerToken,
  );
  assert.strictEqual(rejectFiller.httpStatus, 200);

  const { httpStatus, body } = await callCallable(
    RESPOND_URL,
    { reservationId: target.reservationId, action: "confirm" },
    managerToken,
  );
  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.status, "confirmed");
});

// =======================================================================
// C. Reject (test 9)
// =======================================================================

test("respondToReservation: reject releases the initial hold", async () => {
  const chain = await seedValidReservationChain();
  const { reservationId } = await submitReservationFixture(chain, { partySize: 2 });
  const reservationBefore = await getReservation(reservationId);
  const holdId = reservationBefore.activeHoldId as string;
  const holdBefore = await getHold(holdId);
  const bId = (holdBefore.bucketIds as string[])[0];

  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const { httpStatus, body } = await callCallable(
    RESPOND_URL,
    { reservationId, action: "reject", reasonCode: "restaurantDeclined" },
    managerToken,
  );

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.status, "rejected");
  const holdAfter = await getHold(holdId);
  assert.strictEqual(holdAfter.status, "released");
  const bucketAfter = await getBucket(bId);
  assert.strictEqual(bucketAfter?.heldPartySize, 0);
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.reasonCode, "restaurantDeclined");
  const event = await getEvent(`${reservationId}-rejected`);
  assert.ok(event, "reservationRejected event must exist, committed atomically with the reject");
  assert.strictEqual(event?.type, "reservationRejected");
  assert.strictEqual(event?.reasonCode, "restaurantDeclined");
});

// =======================================================================
// D. Propose change (tests 10-15)
// =======================================================================

test("respondToReservation: proposeChange creates an immutable reservationChangeProposals document", async () => {
  const chain = await seedValidReservationChain();
  const { reservationId } = await submitReservationFixture(chain);
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const proposedTime = alignedFutureIso(120);

  const { httpStatus, body } = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime, proposedAreaId: chain.areaId },
    managerToken,
  );

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.status, "changeProposed");
  const proposalId = body.result?.proposalId as string;
  assert.ok(proposalId);
  const proposalDoc = await admin.firestore().collection("reservationChangeProposals").doc(proposalId).get();
  assert.strictEqual(proposalDoc.exists, true);
  const proposal = proposalDoc.data()!;
  assert.strictEqual(proposal.status, "pendingCustomerResponse");
  assert.strictEqual(proposal.reservationId, reservationId);
  assert.strictEqual(proposal.proposedAreaId, chain.areaId);

  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "changeProposed");
  assert.strictEqual(reservation.activeProposalId, proposalId);
  // Faz R.2 — denormalized proposal snapshot onto the customer-readable
  // reservation doc itself (reservationChangeProposals stays org-staff-only).
  assert.strictEqual(reservation.activeProposalProposedAreaId, chain.areaId);
  assert.ok(reservation.activeProposalProposedTime);
  assert.ok(reservation.activeProposalCustomerResponseDeadlineAt);

  const event = await getEvent(`${reservationId}-changeProposed-${proposalId}`);
  assert.ok(event, "reservationChangeProposed event must exist, committed atomically with the proposal");
  assert.strictEqual(event?.type, "reservationChangeProposed");
});

test("respondToReservation: proposeChange creates an alternative-proposal hold and increments heldPartySize on the proposed buckets", async () => {
  const chain = await seedValidReservationChain();
  const { reservationId } = await submitReservationFixture(chain, { partySize: 3 });
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const proposedTime = alignedFutureIso(120);

  const { body } = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime, proposedAreaId: chain.areaId },
    managerToken,
  );
  const reservation = await getReservation(reservationId);
  const holdId = reservation.activeHoldId as string;
  const hold = await getHold(holdId);
  assert.strictEqual(hold.purpose, "alternativeProposal");
  assert.strictEqual(hold.status, "active");
  assert.strictEqual(hold.proposalId, body.result?.proposalId);
  const bId = (hold.bucketIds as string[])[0];
  const bucket = await getBucket(bId);
  assert.strictEqual(bucket?.heldPartySize, 3);
});

test("respondToReservation: proposeChange on an unavailable proposed slot fails, no proposal created", async () => {
  const chain = await seedValidReservationChain({}, 2);
  const proposedTime = alignedFutureIso(180);
  // Fill the proposed slot/area first with a separate reservation directly confirmed onto it.
  const filler = await submitReservationFixture(chain, { partySize: 2, requestedTime: proposedTime });
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  await callCallable(RESPOND_URL, { reservationId: filler.reservationId, action: "confirm" }, managerToken);

  const { reservationId } = await submitReservationFixture(chain, { partySize: 2 });
  const { httpStatus, body } = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime, proposedAreaId: chain.areaId },
    managerToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "pendingRestaurantApproval");
  assert.strictEqual(reservation.activeProposalId ?? null, null);
});

test("respondToReservation: proposeChange enforces the same minimum-advance and slot-alignment invariants as submitReservation", async () => {
  const chain = await seedValidReservationChain();
  const { reservationId } = await submitReservationFixture(chain);
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);

  const tooSoon = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime: alignedFutureIso(10), proposedAreaId: chain.areaId },
    managerToken,
  );
  assert.strictEqual(tooSoon.httpStatus, 400);
  assert.strictEqual(tooSoon.body.error?.status, "FAILED_PRECONDITION");

  const misaligned = new Date(Date.now() + 60 * 60_000);
  misaligned.setSeconds(7, 0);
  const badSlot = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime: misaligned.toISOString(), proposedAreaId: chain.areaId },
    managerToken,
  );
  assert.strictEqual(badSlot.httpStatus, 400);
  assert.strictEqual(badSlot.body.error?.status, "INVALID_ARGUMENT");
});

test("respondToReservation: a reservation cannot receive a second active proposal while one is still pendingCustomerResponse", async () => {
  const chain = await seedValidReservationChain();
  const { reservationId } = await submitReservationFixture(chain);
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);

  const first = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime: alignedFutureIso(120), proposedAreaId: chain.areaId },
    managerToken,
  );
  assert.strictEqual(first.httpStatus, 200);

  const second = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime: alignedFutureIso(180), proposedAreaId: chain.areaId },
    managerToken,
  );
  assert.strictEqual(second.httpStatus, 400);
  assert.strictEqual(second.body.error?.status, "FAILED_PRECONDITION");
});

test("respondToReservation: two concurrent proposeChange attempts on the same reservation — only one succeeds", async () => {
  const chain = await seedValidReservationChain();
  const { reservationId } = await submitReservationFixture(chain);
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);

  const [a, b] = await Promise.all([
    callCallable(
      RESPOND_URL,
      { reservationId, action: "proposeChange", proposedTime: alignedFutureIso(120), proposedAreaId: chain.areaId },
      managerToken,
    ),
    callCallable(
      RESPOND_URL,
      { reservationId, action: "proposeChange", proposedTime: alignedFutureIso(180), proposedAreaId: chain.areaId },
      managerToken,
    ),
  ]);

  const statuses = [a.httpStatus, b.httpStatus].sort();
  assert.deepStrictEqual(statuses, [200, 400]);
  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "changeProposed");
});

// =======================================================================
// E. Capacity-accounting invariant under concurrency (test 29)
// =======================================================================

test("respondToReservation: confirmed capacity never exceeds area capacity under concurrent fresh-recheck confirms", async () => {
  const chain = await seedValidReservationChain({}, 2);
  const requestedTime = alignedFutureIso(60);
  const filler = await submitReservationFixture(chain, { partySize: 2, requestedTime });
  const a = await submitReservationFixture(chain, { partySize: 2, requestedTime });
  const b = await submitReservationFixture(chain, { partySize: 2, requestedTime });
  assert.strictEqual(a.result.requestedAvailabilityAtSubmission, "unavailable");
  assert.strictEqual(b.result.requestedAvailabilityAtSubmission, "unavailable");

  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const rejectFiller = await callCallable(RESPOND_URL, { reservationId: filler.reservationId, action: "reject" }, managerToken);
  assert.strictEqual(rejectFiller.httpStatus, 200);

  const [ra, rb] = await Promise.all([
    callCallable(RESPOND_URL, { reservationId: a.reservationId, action: "confirm" }, managerToken),
    callCallable(RESPOND_URL, { reservationId: b.reservationId, action: "confirm" }, managerToken),
  ]);

  const statuses = [ra.httpStatus, rb.httpStatus].sort();
  assert.deepStrictEqual(statuses, [200, 400], "exactly one of the two concurrent confirms must win the freed 2-seat capacity");

  const bId = bucketId(chain.branchId, chain.areaId, new Date(requestedTime).toISOString());
  const bucket = await getBucket(bId);
  assert.ok((bucket?.confirmedPartySize as number) <= 2, "confirmedPartySize must never exceed area capacity");
});
