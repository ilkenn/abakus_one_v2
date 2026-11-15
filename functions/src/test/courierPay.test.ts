import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";

/**
 * ADR-085 stage 5 — courier pay rates, shifts and earnings, emulator-backed.
 * Helpers copied from `staffAccounts.test.ts` (per-file duplication precedent).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const CREATE_URL = fn("createStaffAccount");
const SET_RATE_URL = fn("setCourierPayRate");
const GET_PROFILE_URL = fn("getCourierPayProfile");
const START_SHIFT_URL = fn("courierStartShift");
const END_SHIFT_URL = fn("courierEndShift");
const LIST_SHIFTS_URL = fn("listCourierShifts");
const REVIEW_SHIFT_URL = fn("reviewCourierShift");
const EARNINGS_URL = fn("getCourierEarnings");
const MY_PAY_URL = fn("getMyCourierPay");

let app: admin.app.App;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID }); });
after(async () => { await app.delete(); });
const db = () => admin.firestore();

async function callCallable(url: string, data: Record<string, unknown>, idToken?: string) {
  const headers: Record<string, string> = { "Content-Type": "application/json" };
  if (idToken) headers.Authorization = `Bearer ${idToken}`;
  const response = await fetch(url, { method: "POST", headers, body: JSON.stringify({ data }) });
  const body = (await response.json()) as {
    result?: Record<string, unknown>;
    error?: { status?: string; message?: string; details?: { code?: string } };
  };
  return { httpStatus: response.status, body };
}

async function refreshIdToken(refreshToken: string): Promise<string> {
  const response = await fetch(`${AUTH_HOST}/securetoken.googleapis.com/v1/token?key=fake-api-key`, {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken }).toString(),
  });
  return ((await response.json()) as { id_token: string }).id_token;
}

const TEST_RUN_ID = `${Date.now().toString(36)}${Math.random().toString(36).slice(2, 8)}`;
const PHONE_NAMESPACE = String(Math.floor(Math.random() * 900_000) + 100_000);
let counter = 0;
function nextPhone(): string { counter += 1; return `+1556${PHONE_NAMESPACE}${String(counter).padStart(3, "0")}`; }
function nextId(prefix: string): string { counter += 1; return `${prefix}-${TEST_RUN_ID}-${counter}`; }

async function signInWithPhone(phoneNumber: string) {
  const sendRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:sendVerificationCode?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ phoneNumber, recaptchaToken: "x" }) },
  );
  const sendBody = (await sendRes.json()) as { sessionInfo: string };
  const codesRes = await fetch(`${AUTH_HOST}/emulator/v1/projects/${EMULATOR_PROJECT_ID}/verificationCodes`);
  const codes = (await codesRes.json()) as { verificationCodes: { sessionInfo: string; code: string }[] };
  const match = codes.verificationCodes.find((c) => c.sessionInfo === sendBody.sessionInfo)!;
  const signInRes = await fetch(
    `${AUTH_HOST}/identitytoolkit.googleapis.com/v1/accounts:signInWithPhoneNumber?key=fake-api-key`,
    { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify({ sessionInfo: sendBody.sessionInfo, code: match.code }) },
  );
  const body = (await signInRes.json()) as { idToken: string; refreshToken: string; localId: string };
  return { idToken: body.idToken, refreshToken: body.refreshToken, uid: body.localId };
}

async function seedTenant() {
  const organizationId = nextId("org");
  const restaurantId = nextId("restaurant");
  await db().collection("organizations").doc(organizationId).set({ name: "Test Org", isActive: true });
  await db().collection("restaurants").doc(restaurantId).set({ organizationId, name: "Test", isActive: true });
  const branchId = nextId("branch");
  const otherBranchId = nextId("branch");
  for (const id of [branchId, otherBranchId]) {
    await db().collection("branches").doc(id).set({ restaurantId, organizationId, name: "Şube", status: "active", emergencyStopped: false });
  }
  return { organizationId, branchId, otherBranchId };
}

async function bootstrapAdmin(organizationId: string) {
  const { idToken, refreshToken, uid } = await signInWithPhone(nextPhone());
  const bootstrap = await callCallable(BOOTSTRAP_URL, { organizationId }, idToken);
  assert.strictEqual(bootstrap.httpStatus, 200, JSON.stringify(bootstrap.body));
  await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  return { uid, idToken: await refreshIdToken(refreshToken) };
}

async function seededMember(organizationId: string, roles: string[], branchAccess: string[]) {
  const { idToken, refreshToken, uid } = await signInWithPhone(nextPhone());
  await db().collection("memberships").doc(`${organizationId}_${uid}`).set({
    organizationId, uid, roles, branchAccess, restaurantAccess: [], status: "active",
    createdAt: new Date(), updatedAt: new Date(), version: 1, firstName: "Ali", lastName: "Kurye",
  });
  await callCallable(SYNC_CLAIMS_URL, {}, idToken);
  return { uid, idToken: await refreshIdToken(refreshToken) };
}

/** A signed-in courier staff account linked to a courier record (as `setCourier` links it). */
async function linkedCourier(organizationId: string, branchId: string, type = "internal") {
  const member = await seededMember(organizationId, ["courier"], [branchId]);
  const courierId = nextId("courier");
  await db().collection("couriers").doc(courierId).set({
    organizationId, branchId, displayName: "Ali Kurye", phoneNumber: "+905550000009", type, status: "active",
    dispatchStatus: "available", activeOrderIds: [], authUid: member.uid, revision: 1,
  });
  await db().collection("courierAccounts").doc(member.uid).set({
    organizationId, courierId, displayName: "Ali Kurye", type, serviceDistrictIds: [], status: "active",
  });
  return { ...member, courierId };
}

function istanbulToday(): string {
  return new Date(Date.now() + 3 * 3600_000).toISOString().slice(0, 10);
}

test("createStaffAccount: the courier's first rate comes from the same form; a manager cannot set a pool rate", async () => {
  const { organizationId, branchId } = await seedTenant();
  const adminCaller = await bootstrapAdmin(organizationId);
  const manager = await seededMember(organizationId, ["manager"], [branchId]);
  const base = { organizationId, firstName: "Ali", lastName: "Kurye", password: "dogru-sifre-123", roles: ["courier"], branchAccess: [branchId] };

  const shop = await callCallable(CREATE_URL, {
    ...base, phoneNumber: nextPhone(), courierPay: { courierKind: "shop", perPackageMinorUnits: 4000, hourlyMinorUnits: 15000 },
  }, manager.idToken);
  assert.strictEqual(shop.httpStatus, 200, JSON.stringify(shop.body));
  const profile = (await db().collection("courierPayProfiles").doc(`${organizationId}_${shop.body.result!.uid}`).get()).data()!;
  assert.strictEqual(profile.versions.length, 1);
  assert.strictEqual(profile.versions[0].effectiveFromDate, istanbulToday());
  assert.strictEqual(profile.versions[0].hourlyMinorUnits, 15000);

  const poolByManager = await callCallable(CREATE_URL, {
    ...base, phoneNumber: nextPhone(), courierPay: { courierKind: "pool", perPackageMinorUnits: 9000 },
  }, manager.idToken);
  assert.strictEqual(poolByManager.httpStatus, 403, JSON.stringify(poolByManager.body));

  const poolByAdmin = await callCallable(CREATE_URL, {
    ...base, phoneNumber: nextPhone(), courierPay: { courierKind: "pool", perPackageMinorUnits: 9000 },
  }, adminCaller.idToken);
  assert.strictEqual(poolByAdmin.httpStatus, 200, JSON.stringify(poolByAdmin.body));

  const notCourier = await callCallable(CREATE_URL, {
    ...base, roles: ["cashier"], phoneNumber: nextPhone(), courierPay: { courierKind: "shop", perPackageMinorUnits: 1, hourlyMinorUnits: 1 },
  }, adminCaller.idToken);
  assert.strictEqual(notCourier.httpStatus, 400, JSON.stringify(notCourier.body));
});

test("setCourierPayRate: versions are appended, never edited; no back-dating; pool only by admin; only in the manager's branches", async () => {
  const { organizationId, branchId, otherBranchId } = await seedTenant();
  const adminCaller = await bootstrapAdmin(organizationId);
  const manager = await seededMember(organizationId, ["manager"], [branchId]);
  const otherManager = await seededMember(organizationId, ["manager"], [otherBranchId]);
  const courier = await seededMember(organizationId, ["courier"], [branchId]);
  const cashier = await seededMember(organizationId, ["cashier"], [branchId]);
  const rate = { organizationId, targetUid: courier.uid, courierKind: "shop", perPackageMinorUnits: 4000, hourlyMinorUnits: 15000 };

  assert.strictEqual((await callCallable(SET_RATE_URL, rate, manager.idToken)).httpStatus, 200);
  const later = await callCallable(SET_RATE_URL, { ...rate, perPackageMinorUnits: 5000, effectiveFromDate: "2099-01-01" }, manager.idToken);
  assert.strictEqual(later.httpStatus, 400, "more than a year ahead");
  const backdated = await callCallable(SET_RATE_URL, { ...rate, effectiveFromDate: "2020-01-01" }, manager.idToken);
  assert.strictEqual(backdated.body.error?.details?.code, "courierPay/backdated", JSON.stringify(backdated.body));
  assert.strictEqual((await callCallable(SET_RATE_URL, rate, otherManager.idToken)).httpStatus, 403, "another branch's manager");
  assert.strictEqual((await callCallable(SET_RATE_URL, { ...rate, courierKind: "pool", hourlyMinorUnits: null }, manager.idToken)).httpStatus, 403);
  assert.strictEqual((await callCallable(SET_RATE_URL, { ...rate, targetUid: cashier.uid }, adminCaller.idToken)).httpStatus, 400);
  assert.strictEqual((await callCallable(SET_RATE_URL, { ...rate, perPackageMinorUnits: 4500 }, adminCaller.idToken)).httpStatus, 200);

  const profile = await callCallable(GET_PROFILE_URL, { organizationId, targetUid: courier.uid }, manager.idToken);
  assert.strictEqual(profile.httpStatus, 200, JSON.stringify(profile.body));
  const versions = profile.body.result!.versions as Array<Record<string, unknown>>;
  assert.deepStrictEqual(versions.map((v) => v.perPackageMinorUnits), [4000, 4500], "the first version is kept as it was");
  assert.strictEqual((profile.body.result!.current as Record<string, unknown>).perPackageMinorUnits, 4500, "a same-day re-entry wins");
  const audit = await db().collection("auditEvents").where("targetRef", "==", `courierPayProfiles/${organizationId}_${courier.uid}`).get();
  assert.strictEqual(audit.size, 2);
});

test("shifts: courier presses, manager approves/corrects with a reason; the closed shift is paid per minute", async () => {
  const { organizationId, branchId, otherBranchId } = await seedTenant();
  await bootstrapAdmin(organizationId);
  const manager = await seededMember(organizationId, ["manager"], [branchId]);
  const otherManager = await seededMember(organizationId, ["manager"], [otherBranchId]);
  const courier = await linkedCourier(organizationId, branchId);

  const noRate = await callCallable(START_SHIFT_URL, {}, courier.idToken);
  assert.strictEqual(noRate.body.error?.details?.code, "courierShift/no-hourly-rate", JSON.stringify(noRate.body));
  assert.strictEqual((await callCallable(SET_RATE_URL, {
    organizationId, targetUid: courier.uid, courierKind: "shop", perPackageMinorUnits: 4000, hourlyMinorUnits: 12000,
  }, manager.idToken)).httpStatus, 200);

  const start = await callCallable(START_SHIFT_URL, {}, courier.idToken);
  assert.strictEqual(start.httpStatus, 200, JSON.stringify(start.body));
  const shift = start.body.result!.shift as Record<string, unknown>;
  assert.strictEqual(shift.status, "startRequested");
  assert.strictEqual((await callCallable(START_SHIFT_URL, {}, courier.idToken)).body.error?.details?.code, "courierShift/already-open");
  assert.strictEqual((await callCallable(END_SHIFT_URL, {}, courier.idToken)).body.error?.details?.code, "courierShift/start-not-approved");

  const listed = await callCallable(LIST_SHIFTS_URL, { organizationId }, manager.idToken);
  assert.deepStrictEqual((listed.body.result!.shifts as Array<Record<string, unknown>>).map((s) => s.shiftId), [shift.shiftId]);
  const hidden = await callCallable(LIST_SHIFTS_URL, { organizationId }, otherManager.idToken);
  assert.deepStrictEqual(hidden.body.result!.shifts, [], "another branch's manager sees nothing");
  assert.strictEqual((await callCallable(LIST_SHIFTS_URL, { organizationId }, courier.idToken)).httpStatus, 403);

  // Corrected start: 2 hours before the press. Without a reason it is refused.
  const correctedStart = (shift.requestedStartAtMillis as number) - 2 * 3600_000;
  const review = { organizationId, shiftId: shift.shiftId, decision: "approve", approvedAtMillis: correctedStart };
  assert.strictEqual((await callCallable(REVIEW_SHIFT_URL, review, manager.idToken)).body.error?.details?.code, "courierShift/reason-required");
  assert.strictEqual((await callCallable(REVIEW_SHIFT_URL, { ...review, reason: "x" }, otherManager.idToken)).httpStatus, 404);
  const approved = await callCallable(REVIEW_SHIFT_URL, { ...review, reason: "Erken geldi, basmayı unuttu" }, manager.idToken);
  assert.strictEqual(approved.httpStatus, 200, JSON.stringify(approved.body));
  assert.strictEqual((approved.body.result!.shift as Record<string, unknown>).status, "active");

  const end = await callCallable(END_SHIFT_URL, {}, courier.idToken);
  assert.strictEqual(end.httpStatus, 200, JSON.stringify(end.body));
  assert.strictEqual((await callCallable(REVIEW_SHIFT_URL, { organizationId, shiftId: shift.shiftId, decision: "reject" }, manager.idToken)).body.error?.details?.code, "courierShift/end-not-rejectable");
  const closed = await callCallable(REVIEW_SHIFT_URL, { organizationId, shiftId: shift.shiftId, decision: "approve" }, manager.idToken);
  assert.strictEqual(closed.httpStatus, 200, JSON.stringify(closed.body));
  const closedShift = closed.body.result!.shift as Record<string, unknown>;
  assert.strictEqual(closedShift.status, "closed");
  const minutes = closedShift.approvedMinutes as number;
  assert.ok(minutes >= 120 && minutes <= 121, `about two hours, got ${minutes}`);
  assert.strictEqual(closedShift.approvedStartAtMillis, correctedStart, "the approved time is kept");
  assert.strictEqual(closedShift.requestedStartAtMillis, shift.requestedStartAtMillis, "and so is the pressed time");

  const line = (await db().collection("courierEarnings").doc(`shift-${shift.shiftId}`).get()).data()!;
  assert.strictEqual(line.kind, "shift");
  assert.strictEqual(line.quantity, minutes);
  assert.strictEqual(line.unitRateMinorUnits, 12000);
  assert.strictEqual(line.amountMinorUnits, Math.round((minutes * 12000) / 60));

  // A new shift can start again; a rejected start frees it too.
  const second = await callCallable(START_SHIFT_URL, {}, courier.idToken);
  assert.strictEqual(second.httpStatus, 200, JSON.stringify(second.body));
  const rejected = await callCallable(REVIEW_SHIFT_URL, {
    organizationId, shiftId: (second.body.result!.shift as Record<string, unknown>).shiftId, decision: "reject", reason: "Bugün izinli",
  }, manager.idToken);
  assert.strictEqual((rejected.body.result!.shift as Record<string, unknown>).status, "rejected");
  assert.strictEqual((await callCallable(START_SHIFT_URL, {}, courier.idToken)).httpStatus, 200);

  // Earnings: the courier sees its own; a manager its branch; another branch's manager nothing.
  const today = istanbulToday();
  const period = { fromDate: line.earnedDate, toDate: today };
  const mine = await callCallable(MY_PAY_URL, period, courier.idToken);
  assert.strictEqual(mine.httpStatus, 200, JSON.stringify(mine.body));
  assert.strictEqual(mine.body.result!.shiftMinorUnits, line.amountMinorUnits);
  assert.strictEqual((mine.body.result!.openShift as Record<string, unknown>).status, "startRequested");
  assert.strictEqual(mine.body.result!.shiftsEnabled, true);
  const managerView = await callCallable(EARNINGS_URL, { organizationId, ...period }, manager.idToken);
  assert.strictEqual(managerView.httpStatus, 200, JSON.stringify(managerView.body));
  assert.strictEqual(managerView.body.result!.totalMinorUnits, line.amountMinorUnits);
  const otherView = await callCallable(EARNINGS_URL, { organizationId, ...period }, otherManager.idToken);
  assert.deepStrictEqual(otherView.body.result!.couriers, []);
  assert.strictEqual((await callCallable(EARNINGS_URL, { organizationId, ...period }, courier.idToken)).httpStatus, 403);
});

test("shifts: a pool courier has none", async () => {
  const { organizationId, branchId } = await seedTenant();
  await bootstrapAdmin(organizationId);
  const courier = await linkedCourier(organizationId, branchId, "pool");
  const start = await callCallable(START_SHIFT_URL, {}, courier.idToken);
  assert.strictEqual(start.body.error?.details?.code, "courierShift/pool-courier", JSON.stringify(start.body));
  const mine = await callCallable(MY_PAY_URL, { fromDate: istanbulToday(), toDate: istanbulToday() }, courier.idToken);
  assert.strictEqual(mine.body.result!.shiftsEnabled, false);
});
