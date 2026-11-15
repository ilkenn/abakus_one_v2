import { test, before, after } from "node:test";
import assert from "node:assert";
import * as admin from "firebase-admin";
import { getStorage } from "firebase-admin/storage";

/**
 * ADR-085 stage 6A — courier invoices and payments, emulator-backed.
 * Helpers copied from `staffAccounts.test.ts` (per-file duplication precedent).
 */

const EMULATOR_PROJECT_ID = "demo-abakus-one-emulator";
const FUNCTIONS_HOST = "http://127.0.0.1:5001";
const AUTH_HOST = "http://127.0.0.1:9099";
const fn = (name: string) => `${FUNCTIONS_HOST}/${EMULATOR_PROJECT_ID}/us-central1/${name}`;
const SYNC_CLAIMS_URL = fn("syncOwnStaffClaims");
const BOOTSTRAP_URL = fn("bootstrapFirstAdminAccount");
const SET_RATE_URL = fn("setCourierPayRate");
const EARNINGS_URL = fn("getCourierEarnings");
const MY_PAY_URL = fn("getMyCourierPay");
const SET_INVOICING_URL = fn("setCourierInvoicing");
const GRANT_URL = fn("requestCourierUploadGrant");
const PREVIEW_URL = fn("previewCourierInvoice");
const SUBMIT_URL = fn("submitCourierInvoice");
const LIST_INVOICES_URL = fn("listCourierInvoices");
const REVIEW_INVOICE_URL = fn("reviewCourierInvoice");
const PAYMENT_URL = fn("recordCourierPayment");
const FILE_URL = fn("getCourierInvoiceFile");

let app: admin.app.App;
const BUCKET_NAME = `${EMULATOR_PROJECT_ID}.appspot.com`;
before(() => { app = admin.initializeApp({ projectId: EMULATOR_PROJECT_ID, storageBucket: BUCKET_NAME }); });
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
function nextPhone(): string { counter += 1; return `+1557${PHONE_NAMESPACE}${String(counter).padStart(3, "0")}`; }
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

function istanbulDay(offsetDays = 0): string {
  return new Date(Date.now() + 3 * 3600_000 + offsetDays * 86_400_000).toISOString().slice(0, 10);
}

async function seedLine(organizationId: string, branchId: string, staffUid: string, earnedDate: string, amountMinorUnits: number) {
  const id = nextId("line");
  await db().collection("courierEarnings").doc(id).set({
    organizationId, branchId, staffUid, courierId: "c", courierName: "Ali Kurye", kind: "package", sourceId: id,
    orderNumber: "DL-1", rateVersionId: "v1", unitRateMinorUnits: amountMinorUnits, quantity: 1, amountMinorUnits,
    currencyCode: "TRY", earnedAt: admin.firestore.Timestamp.now(), earnedDate, createdAt: admin.firestore.Timestamp.now(),
  });
  return id;
}

/** An invoice file uploaded the way the app does (here with the Admin SDK; the rule is tested in storage-tests). */
async function uploadedGrant(idToken: string, contentType = "application/pdf", upload = true) {
  const grant = await callCallable(GRANT_URL, { purpose: "invoice", contentType }, idToken);
  assert.strictEqual(grant.httpStatus, 200, JSON.stringify(grant.body));
  const { grantId, objectPath } = grant.body.result as { grantId: string; objectPath: string };
  if (upload) await getStorage().bucket(BUCKET_NAME).file(objectPath).save(Buffer.from("%PDF-1.4 test"), { contentType });
  return grantId;
}

async function invoicingCourier() {
  const { organizationId, branchId, otherBranchId } = await seedTenant();
  const adminCaller = await bootstrapAdmin(organizationId);
  const manager = await seededMember(organizationId, ["manager"], [branchId]);
  const otherManager = await seededMember(organizationId, ["manager"], [otherBranchId]);
  const courier = await linkedCourier(organizationId, branchId);
  assert.strictEqual((await callCallable(SET_RATE_URL, {
    organizationId, targetUid: courier.uid, courierKind: "shop", perPackageMinorUnits: 4000, hourlyMinorUnits: 10000,
  }, manager.idToken)).httpStatus, 200);
  return { organizationId, branchId, adminCaller, manager, otherManager, courier };
}

test("invoice: only an invoicing courier sends one; it covers the period's lines plus earlier un-invoiced ones; overlap and reuse refused", async () => {
  const t = await invoicingCourier();
  const inPeriod1 = await seedLine(t.organizationId, t.branchId, t.courier.uid, istanbulDay(-10), 4000);
  await seedLine(t.organizationId, t.branchId, t.courier.uid, istanbulDay(-5), 4000);
  await seedLine(t.organizationId, t.branchId, t.courier.uid, istanbulDay(-40), 4000); // carried in
  await seedLine(t.organizationId, t.branchId, t.courier.uid, istanbulDay(0), 4000); // after the period
  const period = { periodFrom: istanbulDay(-15), periodTo: istanbulDay(-1) };
  const submit = (grantId: string, extra: Record<string, unknown> = {}) => callCallable(SUBMIT_URL, {
    grantId, ...period, invoiceAmountMinorUnits: 14160, invoiceNumber: "ABC2026000001", ...extra,
  }, t.courier.idToken);

  const notInvoicing = await submit(await uploadedGrant(t.courier.idToken));
  assert.strictEqual(notInvoicing.body.error?.details?.code, "courierInvoice/not-invoicing", JSON.stringify(notInvoicing.body));
  assert.strictEqual((await callCallable(SET_INVOICING_URL, {
    organizationId: t.organizationId, targetUid: t.courier.uid, issuesInvoice: true,
  }, t.manager.idToken)).httpStatus, 200);

  const preview = await callCallable(PREVIEW_URL, period, t.courier.idToken);
  assert.strictEqual(preview.httpStatus, 200, JSON.stringify(preview.body));
  assert.strictEqual(preview.body.result!.lineCount, 3);
  assert.strictEqual(preview.body.result!.carriedLineCount, 1);
  assert.strictEqual(preview.body.result!.earnedMinorUnits, 12000);

  const missing = await submit(await uploadedGrant(t.courier.idToken, "application/pdf", false));
  assert.strictEqual(missing.body.error?.details?.code, "courierInvoice/file-missing", JSON.stringify(missing.body));
  assert.strictEqual((await callCallable(GRANT_URL, { purpose: "invoice", contentType: "text/html" }, t.courier.idToken)).httpStatus, 400);

  const grantId = await uploadedGrant(t.courier.idToken);
  const sent = await submit(grantId);
  assert.strictEqual(sent.httpStatus, 200, JSON.stringify(sent.body));
  const invoice = sent.body.result!.invoice as Record<string, unknown>;
  assert.strictEqual(invoice.lineCount, 3);
  assert.strictEqual(invoice.earnedMinorUnits, 12000);
  assert.strictEqual(invoice.differenceMinorUnits, 2160, "VAT on top is allowed and shown");
  assert.strictEqual(invoice.status, "submitted");
  assert.strictEqual((await submit(grantId)).body.error?.details?.code, "courierInvoice/grant-used");
  const overlap = await submit(await uploadedGrant(t.courier.idToken), { periodFrom: istanbulDay(-3), periodTo: istanbulDay(0) });
  assert.strictEqual(overlap.body.error?.details?.code, "courierInvoice/period-overlap", JSON.stringify(overlap.body));
  const stored = (await db().collection("courierInvoices").doc(invoice.invoiceId as string).get()).data()!;
  assert.ok((stored.lineIds as string[]).includes(inPeriod1));

  // A later period picks up only what is left (today's line), never the locked ones.
  const next = await callCallable(PREVIEW_URL, { periodFrom: istanbulDay(0), periodTo: istanbulDay(0) }, t.courier.idToken);
  assert.strictEqual(next.body.result!.lineCount, 1);
});

test("invoice review: a branch manager approves or rejects with a reason; rejection frees the lines; another branch sees nothing", async () => {
  const t = await invoicingCourier();
  await callCallable(SET_INVOICING_URL, { organizationId: t.organizationId, targetUid: t.courier.uid, issuesInvoice: true }, t.manager.idToken);
  await seedLine(t.organizationId, t.branchId, t.courier.uid, istanbulDay(-2), 5000);
  const period = { periodFrom: istanbulDay(-7), periodTo: istanbulDay(-1) };
  const send = async () => (await callCallable(SUBMIT_URL, {
    grantId: await uploadedGrant(t.courier.idToken), ...period, invoiceAmountMinorUnits: 5000, invoiceNumber: "F-1",
  }, t.courier.idToken)).body.result!.invoice as Record<string, unknown>;
  const first = await send();

  const listed = await callCallable(LIST_INVOICES_URL, { organizationId: t.organizationId }, t.manager.idToken);
  assert.deepStrictEqual((listed.body.result!.invoices as Array<Record<string, unknown>>).map((i) => i.invoiceId), [first.invoiceId]);
  assert.strictEqual(listed.body.result!.canRecordPayments, false);
  const hidden = await callCallable(LIST_INVOICES_URL, { organizationId: t.organizationId }, t.otherManager.idToken);
  assert.deepStrictEqual(hidden.body.result!.invoices, []);
  const file = await callCallable(FILE_URL, { invoiceId: first.invoiceId }, t.manager.idToken);
  assert.strictEqual(Buffer.from(file.body.result!.base64 as string, "base64").toString(), "%PDF-1.4 test");
  assert.strictEqual((await callCallable(FILE_URL, { invoiceId: first.invoiceId }, t.otherManager.idToken)).httpStatus, 404);
  assert.strictEqual((await callCallable(FILE_URL, { invoiceId: first.invoiceId }, t.courier.idToken)).httpStatus, 200, "the sender sees its own file");

  const review = { organizationId: t.organizationId, invoiceId: first.invoiceId };
  assert.strictEqual((await callCallable(REVIEW_INVOICE_URL, { ...review, decision: "reject" }, t.manager.idToken)).body.error?.details?.code, "courierInvoice/reason-required");
  assert.strictEqual((await callCallable(REVIEW_INVOICE_URL, { ...review, decision: "reject", reason: "x" }, t.otherManager.idToken)).httpStatus, 404);
  const rejected = await callCallable(REVIEW_INVOICE_URL, { ...review, decision: "reject", reason: "Fatura no hatalı" }, t.manager.idToken);
  assert.strictEqual((rejected.body.result!.invoice as Record<string, unknown>).status, "rejected");

  const second = await send();
  assert.strictEqual(second.lineCount, 1, "the rejected invoice's lines are free again");
  const approved = await callCallable(REVIEW_INVOICE_URL, { organizationId: t.organizationId, invoiceId: second.invoiceId, decision: "approve" }, t.manager.idToken);
  assert.strictEqual((approved.body.result!.invoice as Record<string, unknown>).status, "approved");
  assert.strictEqual((await callCallable(REVIEW_INVOICE_URL, { organizationId: t.organizationId, invoiceId: second.invoiceId, decision: "approve" }, t.manager.idToken)).body.error?.details?.code, "courierInvoice/not-pending");
});

test("payments: admin/owner only; partial then full; never more than the invoice; reversal and advance move the balance", async () => {
  const t = await invoicingCourier();
  await callCallable(SET_INVOICING_URL, { organizationId: t.organizationId, targetUid: t.courier.uid, issuesInvoice: true }, t.manager.idToken);
  await seedLine(t.organizationId, t.branchId, t.courier.uid, istanbulDay(-2), 10000);
  await db().collection("courierPayProfiles").doc(`${t.organizationId}_${t.courier.uid}`).set({ earnedTotalMinorUnits: 10000 }, { merge: true });
  const sent = (await callCallable(SUBMIT_URL, {
    grantId: await uploadedGrant(t.courier.idToken), periodFrom: istanbulDay(-7), periodTo: istanbulDay(-1),
    invoiceAmountMinorUnits: 10000, invoiceNumber: "F-2",
  }, t.courier.idToken)).body.result!.invoice as Record<string, unknown>;
  const pay = (extra: Record<string, unknown>, token = t.adminCaller.idToken) =>
    callCallable(PAYMENT_URL, { organizationId: t.organizationId, kind: "invoicePayment", invoiceId: sent.invoiceId, ...extra }, token);

  assert.strictEqual((await pay({ amountMinorUnits: 1000 })).body.error?.details?.code, "courierPayment/invoice-not-approved");
  await callCallable(REVIEW_INVOICE_URL, { organizationId: t.organizationId, invoiceId: sent.invoiceId, decision: "approve" }, t.manager.idToken);
  assert.strictEqual((await pay({ amountMinorUnits: 1000 }, t.manager.idToken)).body.error?.details?.code, "courierPayment/admin-only");

  const partial = await pay({ amountMinorUnits: 4000, paidDate: istanbulDay(0), note: "Havale" });
  assert.strictEqual(partial.httpStatus, 200, JSON.stringify(partial.body));
  assert.strictEqual(partial.body.result!.invoiceStatus, "partiallyPaid");
  assert.strictEqual((await pay({ amountMinorUnits: 7000 })).body.error?.details?.code, "courierPayment/over-invoice");
  assert.strictEqual((await pay({ amountMinorUnits: 100, paidDate: istanbulDay(2) })).body.error?.details?.code, "courierPayment/future-date");
  const full = await pay({ full: true });
  assert.strictEqual(full.body.result!.invoiceStatus, "paid");
  assert.strictEqual((full.body.result!.payment as Record<string, unknown>).amountMinorUnits, 6000);

  const partialId = (partial.body.result!.payment as Record<string, unknown>).paymentId;
  const reversal = await callCallable(PAYMENT_URL, { organizationId: t.organizationId, kind: "reversal", reversesPaymentId: partialId, note: "Yanlış tutar" }, t.adminCaller.idToken);
  assert.strictEqual(reversal.body.result!.invoiceStatus, "partiallyPaid");
  assert.strictEqual((await callCallable(PAYMENT_URL, { organizationId: t.organizationId, kind: "reversal", reversesPaymentId: partialId }, t.adminCaller.idToken)).body.error?.details?.code, "courierPayment/already-reversed");
  const advance = await callCallable(PAYMENT_URL, { organizationId: t.organizationId, kind: "advance", targetUid: t.courier.uid, amountMinorUnits: 500 }, t.adminCaller.idToken);
  assert.strictEqual(advance.httpStatus, 200, JSON.stringify(advance.body));

  // Balance: earned 100 TL − paid (40 + 60 − 40 + 5 = 65 TL) = 35 TL.
  const mine = await callCallable(MY_PAY_URL, { fromDate: istanbulDay(-7), toDate: istanbulDay(0) }, t.courier.idToken);
  assert.strictEqual(mine.httpStatus, 200, JSON.stringify(mine.body));
  assert.strictEqual(mine.body.result!.issuesInvoice, true);
  assert.strictEqual(mine.body.result!.earnedTotalMinorUnits, 10000);
  assert.strictEqual(mine.body.result!.paidTotalMinorUnits, 6500);
  assert.strictEqual(mine.body.result!.balanceMinorUnits, 3500);
  assert.strictEqual(mine.body.result!.paidInPeriodMinorUnits, 6500);
  assert.strictEqual((mine.body.result!.invoices as Array<Record<string, unknown>>)[0].status, "partiallyPaid");
  const panel = await callCallable(EARNINGS_URL, { organizationId: t.organizationId, fromDate: istanbulDay(-365), toDate: istanbulDay(0) }, t.manager.idToken);
  assert.strictEqual(panel.httpStatus, 200, "a 366-day report is allowed");
  const entry = (panel.body.result!.couriers as Array<Record<string, unknown>>)[0];
  assert.strictEqual(entry.balanceMinorUnits, 3500);
  assert.strictEqual(entry.paidInPeriodMinorUnits, 6500);
  assert.strictEqual((await callCallable(EARNINGS_URL, { organizationId: t.organizationId, fromDate: istanbulDay(-367), toDate: istanbulDay(0) }, t.manager.idToken)).httpStatus, 400);
});

