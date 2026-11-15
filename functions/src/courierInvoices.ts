import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { FieldValue, getFirestore, Timestamp, type Firestore } from "firebase-admin/firestore";
import { getStorage } from "firebase-admin/storage";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId } from "./correlationId";
import { requireCourierAccount } from "./courierPool";
import {
  ACTIVE_INVOICE_STATUSES,
  COURIER_EARNINGS_COLLECTION,
  COURIER_INVOICES_COLLECTION,
  COURIER_PAYMENTS_COLLECTION,
  callerRoles,
  courierPayProfileRef,
  daysBetween,
  istanbulDate,
  isValidDate,
  loadCourierMembership,
  optionalReason,
  serializeInvoice,
  serializePayment,
  type CourierEarningDoc,
  type CourierInvoiceDoc,
  type CourierInvoiceStatus,
  type CourierPayProfileDoc,
  type CourierPaymentDoc,
} from "./courierPay";
import { assertTargetNotProtected, assertWithinScope, resolveStaffScope, type StaffScope } from "./staffScope";

/**
 * ADR-085 stage 6A (product owner approved 2026-11-15) — courier invoices
 * and payments.
 *
 * - **"Fatura Keser"** (`courierPayProfiles.issuesInvoice`): a courier who
 *   invoices sends one per period from the courier app; others (insured
 *   shop couriers) are only paid/advanced by an admin/owner.
 * - **Upload** (`courierUploadGrants`): the courier asks for a one-use,
 *   15-minute grant, uploads to `tenants/{org}/courierDocuments/{uid}/
 *   {grantId}` (`storage.rules`: owner, grant, first write, ≤ 5 MB, the
 *   granted type), then submits. The server checks the object exists.
 * - **Lock by lines, not dates**: an invoice snapshots every earning line
 *   up to its end date not covered by another active (non-rejected)
 *   invoice; a period overlapping an active invoice is refused. A late line
 *   dated inside an invoiced period goes into the next invoice. Rejection
 *   (with a reason) frees the lines.
 * - **Review**: a manager of the courier's branch or an admin/owner
 *   approves or rejects. **Payments** (money out) are admin/owner only:
 *   "Tam Ödendi" / partial against an approved invoice, an advance, or a
 *   reversal of an earlier payment — never edited. Each payment moves the
 *   courier's running balance (`paidTotalMinorUnits`).
 * - The invoice amount may differ from the computed earnings (VAT,
 *   withholding); the difference is shown to the reviewer.
 */
export const COURIER_UPLOAD_GRANTS_COLLECTION = "courierUploadGrants";

const GRANT_TTL_MS = 15 * 60 * 1000;
const MAX_FILE_BYTES = 5 * 1024 * 1024;
const MAX_PERIOD_DAYS = 366;
const MAX_INVOICE_LINES = 5000;
const MAX_INVOICE_NUMBER_LENGTH = 64;
const MAX_AMOUNT_MINOR_UNITS = 100_000_000; // 1.000.000 TL
export const COURIER_DOCUMENT_CONTENT_TYPES: ReadonlySet<string> = new Set(["application/pdf", "image/jpeg", "image/png"]);

export interface CourierUploadGrantDoc {
  organizationId: string;
  staffUid: string;
  purpose: "invoice" | "paymentSlip";
  orderId: string | null;
  contentType: string;
  objectPath: string;
  status: "issued" | "used";
  createdAt: Timestamp;
  expiresAt: Timestamp;
}

function invalid(message: string, code?: string): never {
  throw new HttpsError("invalid-argument", message, code ? { code } : undefined);
}

function precondition(message: string, code: string): never {
  throw new HttpsError("failed-precondition", message, { code });
}

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) invalid(`${field} is required.`);
  return (raw as string).trim();
}

function requireAmount(raw: unknown, field: string): number {
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw <= 0 || raw > MAX_AMOUNT_MINOR_UNITS) {
    invalid(`${field} must be a positive whole number of kuruş.`, "courierInvoice/invalid-amount");
  }
  return raw as number;
}

/** A period up to today (Istanbul), at most a year long. */
export function requireInvoicePeriod(fromRaw: unknown, toRaw: unknown, nowMillis: number) {
  if (!isValidDate(fromRaw) || !isValidDate(toRaw)) invalid("periodFrom and periodTo must be YYYY-MM-DD.", "courierInvoice/invalid-period");
  const periodFrom = fromRaw as string;
  const periodTo = toRaw as string;
  if (periodTo < periodFrom) invalid("periodTo must not be before periodFrom.", "courierInvoice/invalid-period");
  if (periodTo > istanbulDate(nowMillis)) invalid("A period cannot end in the future.", "courierInvoice/invalid-period");
  if (daysBetween(periodFrom, periodTo) > MAX_PERIOD_DAYS) invalid("A period is at most a year.", "courierInvoice/invalid-period");
  return { periodFrom, periodTo };
}

export function periodsOverlap(a: { periodFrom: string; periodTo: string }, b: { periodFrom: string; periodTo: string }): boolean {
  return a.periodFrom <= b.periodTo && b.periodFrom <= a.periodTo;
}

/** Pure: the lines an invoice ending [periodTo] covers — up to that day, not on another active invoice. */
export function invoiceableLines<T extends { id: string; earnedDate: string }>(
  lines: readonly T[],
  periodTo: string,
  lockedLineIds: ReadonlySet<string>,
): T[] {
  return lines.filter((line) => line.earnedDate <= periodTo && !lockedLineIds.has(line.id));
}

/** Pure: an invoice's status after its paid total changes. */
export function invoiceStatusAfterPayment(invoiceAmountMinorUnits: number, paidMinorUnits: number): CourierInvoiceStatus {
  if (paidMinorUnits >= invoiceAmountMinorUnits) return "paid";
  if (paidMinorUnits > 0) return "partiallyPaid";
  return "approved";
}

function inScope(scope: StaffScope, branchIds: readonly string[]): boolean {
  return scope.kind === "organization" || branchIds.some((b) => scope.branches.has(b));
}

async function activeInvoicesOf(db: Firestore, organizationId: string, staffUid: string) {
  const snap = await db.collection(COURIER_INVOICES_COLLECTION).where("staffUid", "==", staffUid).get();
  return snap.docs
    .map((doc) => ({ id: doc.id, invoice: doc.data() as CourierInvoiceDoc }))
    .filter(({ invoice }) => invoice.organizationId === organizationId && ACTIVE_INVOICE_STATUSES.includes(invoice.status));
}

async function linesUpTo(db: Firestore, organizationId: string, staffUid: string, periodTo: string) {
  const snap = await db
    .collection(COURIER_EARNINGS_COLLECTION)
    .where("staffUid", "==", staffUid)
    .where("earnedDate", "<=", periodTo)
    .limit(MAX_INVOICE_LINES)
    .get();
  return snap.docs
    .map((doc) => ({ id: doc.id, ...(doc.data() as CourierEarningDoc) }))
    .filter((line) => line.organizationId === organizationId);
}

/**
 * The staff form's "Fatura Keser" switch. Same authority as a rate: a
 * manager of the courier's branches, or an admin/owner.
 */
export const setCourierInvoicing = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const targetUid = requireString(data.targetUid, "targetUid");
  if (typeof data.issuesInvoice !== "boolean") invalid("issuesInvoice must be true or false.");
  const issuesInvoice = data.issuesInvoice as boolean;
  if (targetUid === request.auth.uid) throw new HttpsError("permission-denied", "Nobody changes their own pay settings.");
  const scope = await resolveStaffScope(request, organizationId);
  const membership = await loadCourierMembership(organizationId, targetUid);
  assertTargetNotProtected(membership);
  assertWithinScope(scope, membership);
  const db = getFirestore();
  const ref = courierPayProfileRef(db, organizationId, targetUid);
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const previous = snap.exists ? (snap.data() as CourierPayProfileDoc).issuesInvoice === true : false;
    if (previous === issuesInvoice) return;
    const now = Timestamp.now();
    tx.set(ref, {
      organizationId, staffUid: targetUid, branchIds: membership.branchAccess,
      ...(snap.exists ? {} : { versions: [] }),
      issuesInvoice, updatedAt: now,
    }, { merge: true });
    writeAuditEvent({
      tx, db, eventId: `${ref.id}-invoicing-${now.toMillis()}`, organizationId,
      type: "courierPay.invoicingSet", targetRef: ref.path,
      previousValue: { issuesInvoice: previous }, newValue: { issuesInvoice },
      actorType: "staff", actorUid: request.auth!.uid, actorRoles: callerRoles(request, organizationId),
      correlationId: generateCorrelationId(), now,
    });
  });
  return { organizationId, targetUid, issuesInvoice };
});

/**
 * A one-use upload grant for the signed-in courier: `invoice` (PDF, JPEG
 * or PNG), or `paymentSlip` (stage 6B: a camera photo of the POS slip or
 * meal-card approval, for one order out for delivery on this courier).
 */
export const requestCourierUploadGrant = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const purpose = data.purpose;
  if (purpose !== "invoice" && purpose !== "paymentSlip") invalid('purpose must be "invoice" or "paymentSlip".');
  const contentType = requireString(data.contentType, "contentType");
  if (!COURIER_DOCUMENT_CONTENT_TYPES.has(contentType)) {
    invalid("An invoice must be a PDF, JPEG or PNG file.", "courierInvoice/invalid-file");
  }
  // Stage 6B — a payment-slip photo is an image, for one order on this courier.
  const orderId = purpose === "paymentSlip" ? requireString(data.orderId, "orderId") : null;
  if (purpose === "paymentSlip" && contentType === "application/pdf") {
    invalid("A payment slip must be a camera photo.", "courierInvoice/invalid-file");
  }
  const db = getFirestore();
  const grantRef = db.collection(COURIER_UPLOAD_GRANTS_COLLECTION).doc();
  return db.runTransaction(async (tx) => {
    const { uid, account, courierId } = await requireCourierAccount(request, tx, db);
    if (orderId) {
      const orderSnap = await tx.get(db.collection("orders").doc(orderId));
      const order = orderSnap.data();
      if (!orderSnap.exists || order!.assignedCourierId !== courierId || order!.organizationId !== account.organizationId) {
        throw new HttpsError("permission-denied", "This order is not assigned to you.");
      }
      if (order!.status !== "outForDelivery") {
        precondition("The order is not out for delivery.", "courierPool/not-out-for-delivery");
      }
    }
    const now = Timestamp.now();
    const objectPath = `tenants/${account.organizationId}/courierDocuments/${uid}/${grantRef.id}`;
    const grant: CourierUploadGrantDoc = {
      organizationId: account.organizationId,
      staffUid: uid,
      purpose: purpose as CourierUploadGrantDoc["purpose"],
      orderId,
      contentType,
      objectPath,
      status: "issued",
      createdAt: now,
      expiresAt: Timestamp.fromMillis(now.toMillis() + GRANT_TTL_MS),
    };
    tx.set(grantRef, grant);
    return { grantId: grantRef.id, objectPath, expiresAtMillis: grant.expiresAt.toMillis() };
  });
});

/** "Fatura Yükle" step 1: what the period would invoice (lines and computed earnings). */
export const previewCourierInvoice = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const { periodFrom, periodTo } = requireInvoicePeriod(data.periodFrom, data.periodTo, Date.now());
  const db = getFirestore();
  const { uid, organizationId } = await db.runTransaction(async (tx) => {
    const { uid, account } = await requireCourierAccount(request, tx, db);
    return { uid, organizationId: account.organizationId };
  });
  const active = await activeInvoicesOf(db, organizationId, uid);
  const overlapping = active.find(({ invoice }) => periodsOverlap(invoice, { periodFrom, periodTo }));
  const locked = new Set(active.flatMap(({ invoice }) => invoice.lineIds));
  const lines = invoiceableLines(await linesUpTo(db, organizationId, uid, periodTo), periodTo, locked);
  return {
    periodFrom,
    periodTo,
    lineCount: lines.length,
    earnedMinorUnits: lines.reduce((sum, line) => sum + line.amountMinorUnits, 0),
    /** Lines from before [periodFrom] that were never invoiced (carried in). */
    carriedLineCount: lines.filter((line) => line.earnedDate < periodFrom).length,
    overlappingInvoiceId: overlapping?.id ?? null,
  };
});

/** "Fatura Yükle" step 2: the uploaded file becomes an invoice and its lines are locked. */
export const submitCourierInvoice = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const grantId = requireString(data.grantId, "grantId");
  const nowMillis = Date.now();
  const { periodFrom, periodTo } = requireInvoicePeriod(data.periodFrom, data.periodTo, nowMillis);
  const invoiceAmountMinorUnits = requireAmount(data.invoiceAmountMinorUnits, "invoiceAmountMinorUnits");
  const invoiceNumber = requireString(data.invoiceNumber, "invoiceNumber");
  if (invoiceNumber.length > MAX_INVOICE_NUMBER_LENGTH) invalid("invoiceNumber is too long.");
  const note = optionalReason(data.note);
  const db = getFirestore();
  const grantRef = db.collection(COURIER_UPLOAD_GRANTS_COLLECTION).doc(grantId);

  // The file must really be there (uploaded under the grant, within limits).
  const preGrant = await grantRef.get();
  if (!preGrant.exists) throw new HttpsError("not-found", "Upload not found.");
  const pre = preGrant.data() as CourierUploadGrantDoc;
  let metadata: { size?: string | number; contentType?: string };
  try {
    [metadata] = await getStorage().bucket().file(pre.objectPath).getMetadata();
  } catch {
    precondition("The invoice file has not been uploaded.", "courierInvoice/file-missing");
  }
  if (Number(metadata!.size ?? 0) > MAX_FILE_BYTES || metadata!.contentType !== pre.contentType) {
    precondition("The uploaded file does not match the upload grant.", "courierInvoice/invalid-file");
  }

  const invoiceRef = db.collection(COURIER_INVOICES_COLLECTION).doc();
  return db.runTransaction(async (tx) => {
    const { uid, account, courier } = await requireCourierAccount(request, tx, db);
    const organizationId = account.organizationId;
    const grantSnap = await tx.get(grantRef);
    const grant = grantSnap.data() as CourierUploadGrantDoc;
    if (grant.staffUid !== uid || grant.organizationId !== organizationId || grant.purpose !== "invoice") {
      throw new HttpsError("not-found", "Upload not found.");
    }
    if (grant.status !== "issued") precondition("This upload was already used.", "courierInvoice/grant-used");
    const profileRef = courierPayProfileRef(db, organizationId, uid);
    const profileSnap = await tx.get(profileRef);
    const profile = profileSnap.exists ? (profileSnap.data() as CourierPayProfileDoc) : null;
    if (profile?.issuesInvoice !== true) {
      precondition("This courier does not send invoices.", "courierInvoice/not-invoicing");
    }
    // Read every active invoice and every line inside the transaction: a
    // concurrent submission conflicts on the profile write below and retries.
    const invoiceSnap = await tx.get(db.collection(COURIER_INVOICES_COLLECTION).where("staffUid", "==", uid));
    const active = invoiceSnap.docs
      .map((doc) => ({ id: doc.id, invoice: doc.data() as CourierInvoiceDoc }))
      .filter(({ invoice }) => invoice.organizationId === organizationId && ACTIVE_INVOICE_STATUSES.includes(invoice.status));
    if (active.some(({ invoice }) => periodsOverlap(invoice, { periodFrom, periodTo }))) {
      precondition("An invoice already covers part of this period.", "courierInvoice/period-overlap");
    }
    const lineSnap = await tx.get(
      db.collection(COURIER_EARNINGS_COLLECTION).where("staffUid", "==", uid).where("earnedDate", "<=", periodTo).limit(MAX_INVOICE_LINES),
    );
    const allLines = lineSnap.docs
      .map((doc) => ({ id: doc.id, ...(doc.data() as CourierEarningDoc) }))
      .filter((line) => line.organizationId === organizationId);
    const locked = new Set(active.flatMap(({ invoice }) => invoice.lineIds));
    const lines = invoiceableLines(allLines, periodTo, locked);
    if (lines.length === 0) precondition("There is nothing to invoice in this period.", "courierInvoice/no-lines");

    const now = Timestamp.fromMillis(nowMillis);
    const invoice: CourierInvoiceDoc = {
      organizationId,
      staffUid: uid,
      courierName: String(courier.displayName ?? ""),
      branchIds: profile!.branchIds ?? [],
      periodFrom,
      periodTo,
      lineIds: lines.map((line) => line.id),
      lineCount: lines.length,
      earnedMinorUnits: lines.reduce((sum, line) => sum + line.amountMinorUnits, 0),
      invoiceAmountMinorUnits,
      invoiceNumber,
      note: note || null,
      filePath: grant.objectPath,
      contentType: grant.contentType,
      status: "submitted",
      rejectReason: null,
      reviewedByUid: null,
      reviewedAt: null,
      paidMinorUnits: 0,
      createdAt: now,
      updatedAt: now,
    };
    tx.set(invoiceRef, invoice);
    tx.update(grantRef, { status: "used" });
    tx.set(profileRef, { invoiceSequence: (profile!.invoiceSequence ?? 0) + 1 }, { merge: true });
    writeAuditEvent({
      tx, db, eventId: `courierInvoice-${invoiceRef.id}-submitted`, organizationId,
      type: "courierInvoice.submitted", targetRef: invoiceRef.path,
      newValue: { periodFrom, periodTo, lineCount: invoice.lineCount, earnedMinorUnits: invoice.earnedMinorUnits, invoiceAmountMinorUnits, invoiceNumber },
      actorType: "courier", actorUid: uid, actorRoles: callerRoles(request, organizationId),
      correlationId: generateCorrelationId(), now,
    });
    return { invoice: serializeInvoice(invoiceRef.id, invoice) };
  });
});

/** Panel: invoices of the caller's branches (all statuses, newest first). */
export const listCourierInvoices = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const scope = await resolveStaffScope(request, organizationId);
  const snap = await getFirestore().collection(COURIER_INVOICES_COLLECTION).where("organizationId", "==", organizationId).get();
  const invoices = snap.docs
    .map((doc) => ({ id: doc.id, invoice: doc.data() as CourierInvoiceDoc }))
    .filter(({ invoice }) => inScope(scope, invoice.branchIds))
    .map(({ id, invoice }) => serializeInvoice(id, invoice))
    .sort((a, b) => b.createdAtMillis - a.createdAtMillis)
    .slice(0, 300);
  return { organizationId, invoices, canRecordPayments: scope.kind === "organization" };
});

/** Approve or (with a reason) reject a sent invoice. Rejection frees its lines. */
export const reviewCourierInvoice = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const invoiceId = requireString(data.invoiceId, "invoiceId");
  const decision = data.decision;
  if (decision !== "approve" && decision !== "reject") invalid('decision must be "approve" or "reject".');
  const reason = optionalReason(data.reason);
  if (decision === "reject" && reason.length === 0) invalid("A reason is required to reject an invoice.", "courierInvoice/reason-required");
  const scope = await resolveStaffScope(request, organizationId);
  const db = getFirestore();
  const ref = db.collection(COURIER_INVOICES_COLLECTION).doc(invoiceId);
  return db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) throw new HttpsError("not-found", "Invoice not found.");
    const invoice = snap.data() as CourierInvoiceDoc;
    if (invoice.organizationId !== organizationId || !inScope(scope, invoice.branchIds)) {
      throw new HttpsError("not-found", "Invoice not found.");
    }
    if (invoice.staffUid === request.auth!.uid) throw new HttpsError("permission-denied", "Nobody reviews their own invoice.");
    if (invoice.status !== "submitted") precondition(`This invoice is already "${invoice.status}".`, "courierInvoice/not-pending");
    const now = Timestamp.now();
    const status: CourierInvoiceStatus = decision === "approve" ? "approved" : "rejected";
    const update = {
      status, rejectReason: decision === "reject" ? reason : null,
      reviewedByUid: request.auth!.uid, reviewedAt: now, updatedAt: now,
    };
    tx.update(ref, update);
    writeAuditEvent({
      tx, db, eventId: `courierInvoice-${invoiceId}-${status}`, organizationId,
      type: `courierInvoice.${status}`, targetRef: ref.path,
      previousValue: { status: invoice.status }, newValue: { status },
      reasonMessage: decision === "reject" ? reason : null,
      actorType: "staff", actorUid: request.auth!.uid, actorRoles: callerRoles(request, organizationId),
      correlationId: generateCorrelationId(), now,
    });
    return { invoice: serializeInvoice(invoiceId, { ...invoice, ...update }) };
  });
});

/**
 * Money out — admin/owner only. `invoicePayment` against an approved or
 * partly paid invoice (`full: true` = "Tam Ödendi", the remainder), an
 * `advance` to any courier, or a `reversal` of an earlier payment. Every
 * payment moves the courier's running balance; none is ever edited.
 */
export const recordCourierPayment = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const kind = data.kind;
  if (kind !== "invoicePayment" && kind !== "advance" && kind !== "reversal") {
    invalid('kind must be "invoicePayment", "advance" or "reversal".');
  }
  const nowMillis = Date.now();
  const paidDate = typeof data.paidDate === "string" && data.paidDate.length > 0 ? data.paidDate : istanbulDate(nowMillis);
  if (!isValidDate(paidDate)) invalid("paidDate must be YYYY-MM-DD.");
  if (paidDate > istanbulDate(nowMillis)) invalid("A payment date cannot be in the future.", "courierPayment/future-date");
  const note = optionalReason(data.note);
  const scope = await resolveStaffScope(request, organizationId);
  if (scope.kind !== "organization") {
    throw new HttpsError("permission-denied", "Only an admin or owner records payments.", { code: "courierPayment/admin-only" });
  }
  const actorUid = request.auth.uid;
  const db = getFirestore();
  const paymentRef = db.collection(COURIER_PAYMENTS_COLLECTION).doc();

  return db.runTransaction(async (tx) => {
    let staffUid: string;
    let invoiceId: string | null = null;
    let invoiceRef: FirebaseFirestore.DocumentReference | null = null;
    let invoice: CourierInvoiceDoc | null = null;
    let reversed: { ref: FirebaseFirestore.DocumentReference; payment: CourierPaymentDoc } | null = null;
    let amount: number;

    if (kind === "reversal") {
      const reversesPaymentId = requireString(data.reversesPaymentId, "reversesPaymentId");
      const originalRef = db.collection(COURIER_PAYMENTS_COLLECTION).doc(reversesPaymentId);
      const originalSnap = await tx.get(originalRef);
      if (!originalSnap.exists) throw new HttpsError("not-found", "Payment not found.");
      const original = originalSnap.data() as CourierPaymentDoc;
      if (original.organizationId !== organizationId) throw new HttpsError("not-found", "Payment not found.");
      if (original.kind === "reversal" || original.reversedByPaymentId) {
        precondition("This payment cannot be reversed again.", "courierPayment/already-reversed");
      }
      reversed = { ref: originalRef, payment: original };
      staffUid = original.staffUid;
      invoiceId = original.invoiceId;
      amount = -original.amountMinorUnits;
    } else if (kind === "invoicePayment") {
      invoiceId = requireString(data.invoiceId, "invoiceId");
      staffUid = "";
      amount = 0;
    } else {
      staffUid = requireString(data.targetUid, "targetUid");
      amount = requireAmount(data.amountMinorUnits, "amountMinorUnits");
    }

    if (invoiceId) {
      invoiceRef = db.collection(COURIER_INVOICES_COLLECTION).doc(invoiceId);
      const invoiceSnap = await tx.get(invoiceRef);
      if (!invoiceSnap.exists) throw new HttpsError("not-found", "Invoice not found.");
      invoice = invoiceSnap.data() as CourierInvoiceDoc;
      if (invoice.organizationId !== organizationId) throw new HttpsError("not-found", "Invoice not found.");
    }
    if (kind === "invoicePayment") {
      if (invoice!.status !== "approved" && invoice!.status !== "partiallyPaid") {
        precondition("Only an approved invoice can be paid.", "courierPayment/invoice-not-approved");
      }
      staffUid = invoice!.staffUid;
      const remaining = invoice!.invoiceAmountMinorUnits - invoice!.paidMinorUnits;
      amount = data.full === true ? remaining : requireAmount(data.amountMinorUnits, "amountMinorUnits");
      if (amount > remaining) invalid("The payment is more than what is left on the invoice.", "courierPayment/over-invoice");
    }
    if (staffUid === actorUid) throw new HttpsError("permission-denied", "Nobody pays themselves.");

    const profileRef = courierPayProfileRef(db, organizationId, staffUid);
    const profileSnap = await tx.get(profileRef);
    const profile = profileSnap.exists ? (profileSnap.data() as CourierPayProfileDoc) : null;
    // An advance names a courier staff member of this organization.
    const member = kind === "advance" ? await loadCourierMembership(organizationId, staffUid) : null;
    const now = Timestamp.fromMillis(nowMillis);
    const payment: CourierPaymentDoc = {
      organizationId,
      staffUid,
      courierName: invoice?.courierName ?? reversed?.payment.courierName ??
        [member?.firstName, member?.lastName].filter((p) => typeof p === "string" && p.length > 0).join(" "),
      branchIds: invoice?.branchIds ?? reversed?.payment.branchIds ?? profile?.branchIds ?? member?.branchAccess ?? [],
      kind: kind as CourierPaymentDoc["kind"],
      amountMinorUnits: amount,
      paidDate,
      invoiceId,
      reversesPaymentId: reversed ? reversed.ref.id : null,
      reversedByPaymentId: null,
      note: note || null,
      createdByUid: actorUid,
      createdAt: now,
    };
    tx.set(paymentRef, payment);
    tx.set(profileRef, { organizationId, staffUid, paidTotalMinorUnits: FieldValue.increment(amount) }, { merge: true });
    if (reversed) tx.update(reversed.ref, { reversedByPaymentId: paymentRef.id });
    let invoiceStatus: CourierInvoiceStatus | null = null;
    if (invoiceRef && invoice) {
      const paid = invoice.paidMinorUnits + amount;
      invoiceStatus = invoiceStatusAfterPayment(invoice.invoiceAmountMinorUnits, paid);
      tx.update(invoiceRef, { paidMinorUnits: paid, status: invoiceStatus, updatedAt: now });
    }
    writeAuditEvent({
      tx, db, eventId: `courierPayment-${paymentRef.id}`, organizationId,
      type: `courierPayment.${kind}`, targetRef: paymentRef.path,
      newValue: { staffUid, amountMinorUnits: amount, paidDate, invoiceId, reversesPaymentId: payment.reversesPaymentId },
      reasonMessage: payment.note,
      actorType: "staff", actorUid, actorRoles: callerRoles(request, organizationId),
      correlationId: generateCorrelationId(), now,
    });
    return { payment: serializePayment(paymentRef.id, payment), invoiceStatus };
  });
});

/**
 * An invoice's file, for the courier who sent it or a reviewer of its
 * branch — returned as base64 (≤ 5 MB), so the Windows panel needs no
 * Storage plugin and nobody gets a shareable link.
 */
export const getCourierInvoiceFile = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const invoiceId = requireString(data.invoiceId, "invoiceId");
  const db = getFirestore();
  const snap = await db.collection(COURIER_INVOICES_COLLECTION).doc(invoiceId).get();
  if (!snap.exists) throw new HttpsError("not-found", "Invoice not found.");
  const invoice = snap.data() as CourierInvoiceDoc;
  if (invoice.staffUid !== request.auth.uid) {
    const scope = await resolveStaffScope(request, invoice.organizationId);
    if (!inScope(scope, invoice.branchIds)) throw new HttpsError("not-found", "Invoice not found.");
  }
  const [bytes] = await getStorage().bucket().file(invoice.filePath).download();
  return { invoiceId, contentType: invoice.contentType, base64: bytes.toString("base64") };
});
