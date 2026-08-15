import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import {
  runReservationResponseTimeoutSweep,
  runReservationProposalExpirySweep,
} from "../reservationSweep";

/**
 * Emulator-backed tests for the reservation sweeps — Faz R.1B §12/§13.
 * Calls the exported plain sweep functions directly (not through
 * `onSchedule`'s own wrapper — the same reasoning `reservationSweep.ts`'s
 * own doc comment gives for exporting them separately: this is the first
 * `onSchedule` usage in the codebase, and there is no existing precedent
 * for triggering a scheduled function through the emulator's HTTP surface
 * in this test suite).
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
async function seedReservationPolicy(branchId: string, restaurantResponseTimeoutMinutes: number, proposalHoldMinutes: number) {
  await admin.firestore().collection("reservationPolicies").doc(branchId).set({
    enabled: true,
    bookingHorizonDays: 60,
    slotIntervalMinutes: 15,
    reservationDurationMinutes: 90,
    maxPartySize: 12,
    customerCancellationCutoffMinutes: 60,
    restaurantResponseTimeoutMinutes,
    proposalHoldMinutes,
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
async function getHold(holdId: string) {
  const doc = await admin.firestore().collection("reservationHolds").doc(holdId).get();
  return doc.data()!;
}
async function getProposal(proposalId: string) {
  const doc = await admin.firestore().collection("reservationChangeProposals").doc(proposalId).get();
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

test("reservationSweep: response-timeout sweep releases the initial hold and rejects the reservation with reasonCode restaurantResponseTimeout", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  // A very short response timeout so requestedTime (90 min out) is the
  // binding min() term — responseDeadlineAt = now + 1 minute.
  await seedReservationPolicy(branchId, 1, 15);
  await seedReservationArea(areaId, branchId, 10);
  await seedWideOpenBranchOperatingHours(branchId);

  const { idToken } = await createRealPhoneUser();
  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId,
      branchId,
      areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
    },
    idToken,
  );
  const reservationId = body.result!.reservationId as string;
  const reservationBefore = await getReservation(reservationId);
  const holdId = reservationBefore.activeHoldId as string;
  const bId = ((await getHold(holdId)).bucketIds as string[])[0];

  // Simulate the deadline having passed — the sweep re-checks
  // `responseDeadlineAt` itself, not merely "an hour later" wall-clock time.
  const sweepNow = new Date(Date.now() + 5 * 60_000);
  const processed = await runReservationResponseTimeoutSweep(admin.firestore(), sweepNow);
  assert.strictEqual(processed, 1);

  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "rejected");
  assert.strictEqual(reservation.reasonCode, "restaurantResponseTimeout");
  const hold = await getHold(holdId);
  assert.strictEqual(hold.status, "released");
  const bucket = await getBucket(bId);
  assert.strictEqual(bucket?.heldPartySize, 0);
  // Faz R.1B.1 — the reservationResponseTimedOut event commits atomically
  // with the sweep's own status transition (same transaction).
  const event = await getEvent(`${reservationId}-responseTimedOut`);
  assert.ok(event, "reservationResponseTimedOut event must exist immediately after the sweep resolves it");
  assert.strictEqual(event?.type, "reservationResponseTimedOut");
});

test("reservationSweep: response-timeout sweep retries are safe — a second run processes zero already-resolved items and writes no duplicate event", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedReservationPolicy(branchId, 1, 15);
  await seedReservationArea(areaId, branchId, 10);
  await seedWideOpenBranchOperatingHours(branchId);

  const { idToken } = await createRealPhoneUser();
  const { body } = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId,
      branchId,
      areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(90),
      ...CONTACT,
    },
    idToken,
  );
  const reservationId = body.result!.reservationId as string;

  const sweepNow = new Date(Date.now() + 5 * 60_000);
  const first = await runReservationResponseTimeoutSweep(admin.firestore(), sweepNow);
  assert.strictEqual(first, 1);
  const recordedAtAfterFirst = (await getEvent(`${reservationId}-responseTimedOut`))?.recordedAt;

  const second = await runReservationResponseTimeoutSweep(admin.firestore(), sweepNow);
  assert.strictEqual(second, 0);
  // Faz R.1B.1 — the second sweep run's query no longer matches this
  // already-resolved reservation at all, so its transaction body (and
  // therefore writeReservationEvent) never runs a second time.
  const eventAfterSecond = await getEvent(`${reservationId}-responseTimedOut`);
  assert.strictEqual(eventAfterSecond?.recordedAt, recordedAtAfterFirst, "sweep retry must not duplicate/rewrite the timeout event");
});

test("reservationSweep: proposal-expiry sweep releases the alternative hold exactly once and returns the reservation to pendingRestaurantApproval", async () => {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  const branchId = nextId("branch");
  const areaId = nextId("area");
  await seedOrganization(organizationId);
  await seedRestaurant(restaurantId, organizationId);
  await seedBranch(branchId, restaurantId, organizationId);
  await seedReservationPolicy(branchId, 120, 1); // 1-minute proposal hold
  await seedReservationArea(areaId, branchId, 10);
  await seedWideOpenBranchOperatingHours(branchId);

  const { idToken } = await createRealPhoneUser();
  const submit = await callCallable(
    SUBMIT_URL,
    {
      submissionKey: nextId("key"),
      restaurantId,
      branchId,
      areaId,
      partySize: 2,
      requestedTime: alignedFutureIso(60),
      ...CONTACT,
    },
    idToken,
  );
  const reservationId = submit.body.result!.reservationId as string;
  const managerToken = await mintStaffIdToken(organizationId, ["manager"]);
  const propose = await callCallable(
    RESPOND_URL,
    {
      reservationId,
      action: "proposeChange",
      proposedTime: alignedFutureIso(120),
      proposedAreaId: areaId,
    },
    managerToken,
  );
  const proposalId = propose.body.result!.proposalId as string;
  const proposalBefore = await getProposal(proposalId);
  const holdId = proposalBefore.holdId as string;
  const bId = ((await getHold(holdId)).bucketIds as string[])[0];

  const sweepNow = new Date(Date.now() + 5 * 60_000);
  const processedFirst = await runReservationProposalExpirySweep(admin.firestore(), sweepNow);
  assert.strictEqual(processedFirst, 1);
  const eventId = `${reservationId}-changeExpired-${proposalId}`;
  const eventAfterFirst = await getEvent(eventId);
  assert.ok(eventAfterFirst, "reservationChangeExpired event must exist immediately after the sweep resolves it");
  assert.strictEqual(eventAfterFirst?.type, "reservationChangeExpired");

  const processedSecond = await runReservationProposalExpirySweep(admin.firestore(), sweepNow);
  assert.strictEqual(processedSecond, 0, "already-expired proposals must not be reprocessed");
  const eventAfterSecond = await getEvent(eventId);
  assert.strictEqual(eventAfterSecond?.recordedAt, eventAfterFirst?.recordedAt, "sweep retry must not duplicate/rewrite the expiry event");

  const proposal = await getProposal(proposalId);
  assert.strictEqual(proposal.status, "expired");
  const hold = await getHold(holdId);
  assert.strictEqual(hold.status, "released");
  const bucket = await getBucket(bId);
  assert.strictEqual(bucket?.heldPartySize, 0, "bucket heldPartySize must never go negative and must be exactly zero after a single release");

  const reservation = await getReservation(reservationId);
  assert.strictEqual(reservation.status, "pendingRestaurantApproval");
  assert.strictEqual(reservation.activeProposalId, null);
  // Faz R.2 — the denormalized proposal snapshot is cleared on expiry too.
  assert.strictEqual(reservation.activeProposalProposedTime, null);
  assert.strictEqual(reservation.activeProposalProposedAreaId, null);
  assert.strictEqual(reservation.activeProposalCustomerResponseDeadlineAt, null);
});
