import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * Emulator-backed tests for `respondToProposedChange` — Faz R.1B. Mirrors
 * `submitReservation.test.ts`/`respondToReservation.test.ts`'s exact
 * pattern. Uses `respondToReservation`'s own `proposeChange` action to set
 * up each fixture's `changeProposed` state — this is intentional: it
 * exercises the two callables' real hand-off, not a synthetic shortcut.
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const SUBMIT_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/submitReservation`;
const RESPOND_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/respondToReservation`;
const RESPOND_PROPOSAL_URL = `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/respondToProposedChange`;

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

async function mintStaffIdToken(organizationId: string, roles: string[]): Promise<string> {
  const { refreshToken, uid } = await signUpAnonymously();
  await admin.auth().setCustomUserClaims(uid, {
    organizationAccess: [organizationId],
    roles: { [organizationId]: roles },
  });
  return refreshIdToken(refreshToken);
}

async function createAnonymousUser(): Promise<{ idToken: string; uid: string }> {
  const { idToken, uid } = await signUpAnonymously();
  return { idToken, uid };
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
async function seedReservationPolicy(branchId: string) {
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
async function seedValidReservationChain(capacity = 10) {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedReservationPolicy(branchId);
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

async function getReservation(reservationId: string) {
  const doc = await admin.firestore().collection("reservations").doc(reservationId).get();
  return doc.data()!;
}
async function getProposal(proposalId: string) {
  const doc = await admin.firestore().collection("reservationChangeProposals").doc(proposalId).get();
  return doc.data()!;
}
async function getHold(holdId: string) {
  const doc = await admin.firestore().collection("reservationHolds").doc(holdId).get();
  return doc.data()!;
}
async function getBucket(id: string) {
  const doc = await admin.firestore().collection("reservationSlotOccupancy").doc(id).get();
  return doc.data();
}
async function getEvent(eventId: string) {
  const doc = await admin.firestore().collection("reservationEvents").doc(eventId).get();
  return doc.exists ? doc.data() : null;
}

/** A submitted reservation with a staff-created change proposal, ready for the owning customer to respond to. */
async function seedProposedChangeFixture(capacity = 10) {
  const chain = await seedValidReservationChain(capacity);
  const { idToken: customerIdToken } = await createRealPhoneUser();
  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId: chain.restaurantId,
      branchId: chain.branchId,
      areaId: chain.areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
    },
    customerIdToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const managerToken = await mintStaffIdToken(chain.organizationId, ["manager"]);
  const proposedTime = alignedFutureIso(120);
  const propose = await callCallable(
    RESPOND_URL,
    { reservationId, action: "proposeChange", proposedTime, proposedAreaId: chain.areaId },
    managerToken,
  );
  const proposalId = propose.body.result!.proposalId as string;
  return { chain, reservationId, proposalId, customerIdToken, managerToken, proposedTime };
}

// =======================================================================
// A. Authorization / ownership (tests 16-17)
// =======================================================================

test("respondToProposedChange: an anonymous customer identity cannot respond — permission-denied", async () => {
  const fixture = await seedProposedChangeFixture();
  const { idToken } = await createAnonymousUser();

  const { httpStatus, body } = await callCallable(
    RESPOND_PROPOSAL_URL,
    { reservationId: fixture.reservationId, proposalId: fixture.proposalId, action: "accept" },
    idToken,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

test("respondToProposedChange: a customer who does not own the reservation is rejected — permission-denied", async () => {
  const fixture = await seedProposedChangeFixture();
  const { idToken: attackerToken } = await createRealPhoneUser();

  const { httpStatus, body } = await callCallable(
    RESPOND_PROPOSAL_URL,
    { reservationId: fixture.reservationId, proposalId: fixture.proposalId, action: "accept" },
    attackerToken,
  );

  assert.strictEqual(httpStatus, 403);
  assert.strictEqual(body.error?.status, "PERMISSION_DENIED");
});

// =======================================================================
// B. Accept (tests 18-20)
// =======================================================================

test("respondToProposedChange: the owning customer can accept a pending proposal", async () => {
  const fixture = await seedProposedChangeFixture();

  const { httpStatus, body } = await callCallable(
    RESPOND_PROPOSAL_URL,
    { reservationId: fixture.reservationId, proposalId: fixture.proposalId, action: "accept" },
    fixture.customerIdToken,
  );

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.status, "confirmed");
  const reservation = await getReservation(fixture.reservationId);
  assert.strictEqual(reservation.status, "confirmed");
  assert.strictEqual(reservation.activeProposalId, null);
  assert.strictEqual(reservation.activeHoldId, null);
  assert.strictEqual(
    new Date(reservation.confirmedTime.toDate()).toISOString(),
    fixture.proposedTime,
  );
  // Faz R.2 — the denormalized proposal snapshot is cleared on accept.
  assert.strictEqual(reservation.activeProposalProposedTime, null);
  assert.strictEqual(reservation.activeProposalProposedAreaId, null);
  assert.strictEqual(reservation.activeProposalCustomerResponseDeadlineAt, null);
  // Faz R.1B.1 — the reservationChangeAccepted event commits atomically
  // with the accept transaction.
  const event = await getEvent(`${fixture.reservationId}-changeAccepted-${fixture.proposalId}`);
  assert.ok(event, "reservationChangeAccepted event must exist immediately after a successful accept");
  assert.strictEqual(event?.type, "reservationChangeAccepted");
});

test("respondToProposedChange: accept converts the hold's heldPartySize into confirmedPartySize on the proposed buckets", async () => {
  const fixture = await seedProposedChangeFixture();
  const proposal = await getProposal(fixture.proposalId);
  const holdBefore = await getHold(proposal.holdId as string);
  const bId = (holdBefore.bucketIds as string[])[0];
  const bucketBefore = await getBucket(bId);
  assert.strictEqual(bucketBefore?.heldPartySize, 2);

  await callCallable(
    RESPOND_PROPOSAL_URL,
    { reservationId: fixture.reservationId, proposalId: fixture.proposalId, action: "accept" },
    fixture.customerIdToken,
  );

  const holdAfter = await getHold(proposal.holdId as string);
  assert.strictEqual(holdAfter.status, "consumed");
  const bucketAfter = await getBucket(bId);
  assert.strictEqual(bucketAfter?.heldPartySize, 0);
  assert.strictEqual(bucketAfter?.confirmedPartySize, 2);
});

test("respondToProposedChange: duplicate accept (retry) is safe", async () => {
  const fixture = await seedProposedChangeFixture();

  const first = await callCallable(
    RESPOND_PROPOSAL_URL,
    { reservationId: fixture.reservationId, proposalId: fixture.proposalId, action: "accept" },
    fixture.customerIdToken,
  );
  assert.strictEqual(first.httpStatus, 200);
  assert.strictEqual(first.body.result?.duplicate, false);
  const eventId = `${fixture.reservationId}-changeAccepted-${fixture.proposalId}`;
  const recordedAtAfterFirst = (await getEvent(eventId))?.recordedAt;

  const second = await callCallable(
    RESPOND_PROPOSAL_URL,
    { reservationId: fixture.reservationId, proposalId: fixture.proposalId, action: "accept" },
    fixture.customerIdToken,
  );
  assert.strictEqual(second.httpStatus, 200);
  assert.strictEqual(second.body.result?.duplicate, true);

  const proposal = await getProposal(fixture.proposalId);
  const bId = ((await getHold(proposal.holdId as string)).bucketIds as string[])[0];
  const bucket = await getBucket(bId);
  assert.strictEqual(bucket?.confirmedPartySize, 2);
  // Faz R.1B.1 — duplicate accept short-circuits before reaching
  // writeReservationEvent, so no second/duplicate event is written.
  const eventAfterSecond = await getEvent(eventId);
  assert.strictEqual(eventAfterSecond?.recordedAt, recordedAtAfterFirst);
});

// =======================================================================
// C. Reject (tests 21-23)
// =======================================================================

test("respondToProposedChange: reject releases the proposal's hold", async () => {
  const fixture = await seedProposedChangeFixture();
  const proposal = await getProposal(fixture.proposalId);
  const bId = ((await getHold(proposal.holdId as string)).bucketIds as string[])[0];

  const { httpStatus, body } = await callCallable(
    RESPOND_PROPOSAL_URL,
    { reservationId: fixture.reservationId, proposalId: fixture.proposalId, action: "reject" },
    fixture.customerIdToken,
  );

  assert.strictEqual(httpStatus, 200);
  assert.strictEqual(body.result?.status, "pendingRestaurantApproval");
  const holdAfter = await getHold(proposal.holdId as string);
  assert.strictEqual(holdAfter.status, "released");
  const bucketAfter = await getBucket(bId);
  assert.strictEqual(bucketAfter?.heldPartySize, 0);
  const event = await getEvent(`${fixture.reservationId}-changeRejected-${fixture.proposalId}`);
  assert.ok(event, "reservationChangeRejected event must exist, committed atomically with the reject");
  assert.strictEqual(event?.type, "reservationChangeRejected");
});

test("respondToProposedChange: reject returns the reservation to pendingRestaurantApproval — not terminal", async () => {
  const fixture = await seedProposedChangeFixture();

  await callCallable(
    RESPOND_PROPOSAL_URL,
    { reservationId: fixture.reservationId, proposalId: fixture.proposalId, action: "reject" },
    fixture.customerIdToken,
  );

  const reservation = await getReservation(fixture.reservationId);
  assert.strictEqual(reservation.status, "pendingRestaurantApproval");
  assert.strictEqual(reservation.activeProposalId, null);
  // Faz R.2 — the denormalized proposal snapshot is cleared on reject too.
  assert.strictEqual(reservation.activeProposalProposedTime, null);
  assert.strictEqual(reservation.activeProposalProposedAreaId, null);
  assert.strictEqual(reservation.activeProposalCustomerResponseDeadlineAt, null);
});

test("respondToProposedChange: after a customer rejects a proposal, staff can propose again", async () => {
  const fixture = await seedProposedChangeFixture();
  await callCallable(
    RESPOND_PROPOSAL_URL,
    { reservationId: fixture.reservationId, proposalId: fixture.proposalId, action: "reject" },
    fixture.customerIdToken,
  );

  const secondProposal = await callCallable(
    RESPOND_URL,
    {
      reservationId: fixture.reservationId,
      action: "proposeChange",
      proposedTime: alignedFutureIso(180),
      proposedAreaId: fixture.chain.areaId,
    },
    fixture.managerToken,
  );

  assert.strictEqual(secondProposal.httpStatus, 200);
  assert.strictEqual(secondProposal.body.result?.status, "changeProposed");
  assert.notStrictEqual(secondProposal.body.result?.proposalId, fixture.proposalId);
});

test("respondToProposedChange: an expired proposal cannot be accepted", async () => {
  const fixture = await seedProposedChangeFixture();
  const proposal = await getProposal(fixture.proposalId);
  const holdId = proposal.holdId as string;
  await admin.firestore().collection("reservationHolds").doc(holdId).set(
    { expiresAt: new Date(Date.now() - 60_000) },
    { merge: true },
  );

  const { httpStatus, body } = await callCallable(
    RESPOND_PROPOSAL_URL,
    { reservationId: fixture.reservationId, proposalId: fixture.proposalId, action: "accept" },
    fixture.customerIdToken,
  );

  assert.strictEqual(httpStatus, 400);
  assert.strictEqual(body.error?.status, "FAILED_PRECONDITION");
  const reservation = await getReservation(fixture.reservationId);
  assert.strictEqual(reservation.status, "changeProposed");
});
