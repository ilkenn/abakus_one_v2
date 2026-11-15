import { onCall, HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import { FieldValue, getFirestore, Timestamp, type DocumentData, type Firestore, type Transaction } from "firebase-admin/firestore";
import { shouldEnforceAppCheck } from "./appCheckConfig";
import { writeAuditEvent } from "./auditEvents";
import { generateCorrelationId } from "./correlationId";
import { requireCourierAccount } from "./courierPool";
import { assertTargetNotProtected, assertWithinScope, resolveStaffScope, type StaffScope } from "./staffScope";
import { membershipId, type MembershipDoc } from "./staffMembership";

/**
 * ADR-085 stage 5 (product owner approved 2026-11-15) — courier pay,
 * shifts and earnings. Everything here is written by the server only
 * (`firestore.rules` default-deny covers every collection below); the
 * panel and the courier app read through the callables in this file.
 *
 * - **Pay rates** (`courierPayProfiles/{org}_{uid}`): per courier staff
 *   account, an append-only list of effective-dated versions. A shop
 *   courier has an hourly rate and a per-package rate; a pool courier a
 *   per-package rate only. A version is never edited — a new one
 *   supersedes it from its start date, which is today at the earliest
 *   (no back-dating). A shop courier's rate is set by a manager of its
 *   branch or by an admin/owner; a pool courier's by an admin/owner only.
 * - **Shifts** (`courierShifts`): shop couriers only. The courier presses
 *   "Vardiya Başlat", a manager approves (or corrects the time, with a
 *   reason, or rejects); the courier presses "Vardiya Bitir", a manager
 *   approves or corrects. The pressed and the approved times are both
 *   kept. `courierShiftPointers/{org}_{uid}` holds the open shift, so a
 *   courier has at most one.
 * - **Earnings** (`courierEarnings`): one line per settled package (written
 *   by `settleCourierReturn`, when the cashier closes the order) and one
 *   per closed shift (approved minutes × hourly rate, per minute, no
 *   rounding of time; the money is rounded to the kuruş). The rate in
 *   force is copied into the line, so a later rate change never alters a
 *   written line.
 * - **Who sees what**: a courier its own earnings; a manager its branches';
 *   an admin/owner the whole organization.
 */
export const COURIER_PAY_PROFILES_COLLECTION = "courierPayProfiles";
export const COURIER_SHIFTS_COLLECTION = "courierShifts";
export const COURIER_SHIFT_POINTERS_COLLECTION = "courierShiftPointers";
export const COURIER_EARNINGS_COLLECTION = "courierEarnings";
/** Stage 6A — invoices a courier sends, and payments/advances recorded against its balance. */
export const COURIER_INVOICES_COLLECTION = "courierInvoices";
export const COURIER_PAYMENTS_COLLECTION = "courierPayments";

export type CourierInvoiceStatus = "submitted" | "approved" | "partiallyPaid" | "paid" | "rejected";

export interface CourierInvoiceDoc {
  organizationId: string;
  staffUid: string;
  courierName: string;
  /** The courier's branches when it was sent (who may review it). */
  branchIds: string[];
  periodFrom: string;
  periodTo: string;
  /** The earning lines this invoice covers (locked while it is not rejected). */
  lineIds: string[];
  lineCount: number;
  /** What the system computed for those lines. */
  earnedMinorUnits: number;
  /** What the invoice says (may differ: VAT, withholding). */
  invoiceAmountMinorUnits: number;
  invoiceNumber: string;
  note: string | null;
  filePath: string;
  contentType: string;
  status: CourierInvoiceStatus;
  rejectReason: string | null;
  reviewedByUid: string | null;
  reviewedAt: Timestamp | null;
  paidMinorUnits: number;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export type CourierPaymentKind = "invoicePayment" | "advance" | "reversal";

export interface CourierPaymentDoc {
  organizationId: string;
  staffUid: string;
  courierName: string;
  branchIds: string[];
  kind: CourierPaymentKind;
  /** Negative for a reversal. */
  amountMinorUnits: number;
  paidDate: string;
  invoiceId: string | null;
  reversesPaymentId: string | null;
  reversedByPaymentId: string | null;
  note: string | null;
  createdByUid: string;
  createdAt: Timestamp;
}

export const ACTIVE_INVOICE_STATUSES: readonly CourierInvoiceStatus[] = ["submitted", "approved", "partiallyPaid", "paid"];

export function serializeInvoice(id: string, invoice: CourierInvoiceDoc) {
  return {
    invoiceId: id,
    staffUid: invoice.staffUid,
    courierName: invoice.courierName,
    periodFrom: invoice.periodFrom,
    periodTo: invoice.periodTo,
    lineCount: invoice.lineCount,
    earnedMinorUnits: invoice.earnedMinorUnits,
    invoiceAmountMinorUnits: invoice.invoiceAmountMinorUnits,
    differenceMinorUnits: invoice.invoiceAmountMinorUnits - invoice.earnedMinorUnits,
    invoiceNumber: invoice.invoiceNumber,
    note: invoice.note,
    contentType: invoice.contentType,
    status: invoice.status,
    rejectReason: invoice.rejectReason,
    paidMinorUnits: invoice.paidMinorUnits,
    remainingMinorUnits: Math.max(0, invoice.invoiceAmountMinorUnits - invoice.paidMinorUnits),
    createdAtMillis: invoice.createdAt.toMillis(),
  };
}

export function serializePayment(id: string, payment: CourierPaymentDoc) {
  return {
    paymentId: id,
    staffUid: payment.staffUid,
    courierName: payment.courierName,
    kind: payment.kind,
    amountMinorUnits: payment.amountMinorUnits,
    paidDate: payment.paidDate,
    invoiceId: payment.invoiceId,
    reversedByPaymentId: payment.reversedByPaymentId,
    note: payment.note,
    createdAtMillis: payment.createdAt.toMillis(),
  };
}

/** Running balance: everything earned minus everything paid (advances and reversals included). */
export function balanceOf(profile: CourierPayProfileDoc | null) {
  const earned = profile?.earnedTotalMinorUnits ?? 0;
  const paid = profile?.paidTotalMinorUnits ?? 0;
  return { earnedTotalMinorUnits: earned, paidTotalMinorUnits: paid, balanceMinorUnits: earned - paid };
}

export type CourierPayKind = "shop" | "pool";

export interface CourierPayRateVersion {
  versionId: string;
  sequence: number;
  courierKind: CourierPayKind;
  perPackageMinorUnits: number;
  /** Shop couriers only; `null` for a pool courier. */
  hourlyMinorUnits: number | null;
  currencyCode: string;
  /** Europe/Istanbul calendar date, `YYYY-MM-DD`. */
  effectiveFromDate: string;
  createdAt: Timestamp;
  createdByUid: string;
}

export interface CourierPayProfileDoc {
  organizationId: string;
  staffUid: string;
  /** The staff account's branches when the profile last changed. */
  branchIds: string[];
  versions: CourierPayRateVersion[];
  updatedAt: Timestamp;
  /** Stage 6A — the courier sends an invoice for its earnings ("Fatura Keser"). */
  issuesInvoice?: boolean;
  /** Stage 6A — running totals: every earning line written, every payment recorded. */
  earnedTotalMinorUnits?: number;
  paidTotalMinorUnits?: number;
  /** Stage 6A — bumped by every invoice submission (serializes them per courier). */
  invoiceSequence?: number;
}

export type CourierShiftStatus = "startRequested" | "active" | "endRequested" | "closed" | "rejected";

export interface CourierShiftDoc {
  organizationId: string;
  branchId: string;
  staffUid: string;
  courierId: string;
  courierName: string;
  status: CourierShiftStatus;
  requestedStartAt: Timestamp;
  approvedStartAt: Timestamp | null;
  startReviewedByUid: string | null;
  startAdjustReason: string | null;
  requestedEndAt: Timestamp | null;
  approvedEndAt: Timestamp | null;
  endReviewedByUid: string | null;
  endAdjustReason: string | null;
  /** The manager ended a shift the courier forgot to end. */
  closedByManager?: boolean;
  rejectReason: string | null;
  approvedMinutes: number | null;
  earningLineId: string | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
}

export type CourierEarningKind = "package" | "shift";

export interface CourierEarningDoc {
  organizationId: string;
  branchId: string;
  staffUid: string;
  courierId: string | null;
  courierName: string;
  kind: CourierEarningKind;
  /** The order (package) or the shift the line pays for. */
  sourceId: string;
  orderNumber: string | null;
  rateVersionId: string;
  /** Per package, or per hour for a shift. */
  unitRateMinorUnits: number;
  /** 1 for a package; the approved minutes for a shift. */
  quantity: number;
  amountMinorUnits: number;
  currencyCode: string;
  earnedAt: Timestamp;
  earnedDate: string;
  createdAt: Timestamp;
}

const MAX_RATE_MINOR_UNITS = 10_000_000; // 100.000 TL
const MAX_REASON_LENGTH = 300;
const MAX_EFFECTIVE_DAYS_AHEAD = 366;
const MAX_PERIOD_DAYS = 366; // stage 6A: a yearly report
const MAX_ADJUST_MS = 12 * 60 * 60 * 1000;
const MAX_SHIFT_MS = 24 * 60 * 60 * 1000;
const MAX_EARNING_LINES = 5000;
const ISTANBUL_OFFSET_MS = 3 * 60 * 60 * 1000; // UTC+3 all year since 2016
const DAY_MS = 24 * 60 * 60 * 1000;
const DATE_PATTERN = /^\d{4}-\d{2}-\d{2}$/;

// ---------------------------------------------------------------------------
// Pure helpers
// ---------------------------------------------------------------------------

/** The Europe/Istanbul calendar date of [millis], `YYYY-MM-DD`. */
export function istanbulDate(millis: number): string {
  return new Date(millis + ISTANBUL_OFFSET_MS).toISOString().slice(0, 10);
}

/** Whole days from [from] to [to] (both `YYYY-MM-DD`). */
export function daysBetween(from: string, to: string): number {
  return Math.round((Date.parse(`${to}T00:00:00Z`) - Date.parse(`${from}T00:00:00Z`)) / DAY_MS);
}

export function isValidDate(value: unknown): value is string {
  if (typeof value !== "string" || !DATE_PATTERN.test(value)) return false;
  const parsed = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(parsed.getTime()) && parsed.toISOString().slice(0, 10) === value;
}

export interface CourierPayRateInput {
  courierKind: CourierPayKind;
  perPackageMinorUnits: number;
  hourlyMinorUnits: number | null;
}

function invalid(message: string, code?: string): never {
  throw new HttpsError("invalid-argument", message, code ? { code } : undefined);
}

function denied(message: string, code?: string): never {
  throw new HttpsError("permission-denied", message, code ? { code } : undefined);
}

function precondition(message: string, code: string): never {
  throw new HttpsError("failed-precondition", message, { code });
}

function rateAmount(value: unknown, field: string): number {
  if (typeof value !== "number" || !Number.isInteger(value) || value < 0 || value > MAX_RATE_MINOR_UNITS) {
    invalid(`${field} must be a whole number of kuruş between 0 and ${MAX_RATE_MINOR_UNITS}.`, "courierPay/invalid-rate");
  }
  return value as number;
}

/** Validates a rate as typed in the panel: pool = per package only; shop = hourly + per package. */
export function parseCourierPayRateInput(raw: unknown): CourierPayRateInput {
  if (typeof raw !== "object" || raw === null) invalid("courierPay must be an object.", "courierPay/invalid-rate");
  const data = raw as Record<string, unknown>;
  const kind = data.courierKind;
  if (kind !== "shop" && kind !== "pool") invalid('courierKind must be "shop" or "pool".', "courierPay/invalid-rate");
  const perPackageMinorUnits = rateAmount(data.perPackageMinorUnits, "perPackageMinorUnits");
  let hourlyMinorUnits: number | null = null;
  if (kind === "shop") {
    hourlyMinorUnits = rateAmount(data.hourlyMinorUnits, "hourlyMinorUnits");
  } else if (data.hourlyMinorUnits !== undefined && data.hourlyMinorUnits !== null && data.hourlyMinorUnits !== 0) {
    invalid("A pool courier is paid per package only.", "courierPay/invalid-rate");
  }
  if (perPackageMinorUnits === 0 && (hourlyMinorUnits ?? 0) === 0) {
    invalid("At least one rate must be above zero.", "courierPay/invalid-rate");
  }
  return { courierKind: kind as CourierPayKind, perPackageMinorUnits, hourlyMinorUnits };
}

/** The version in force on [date]: the latest start on or before it; a same-day re-entry wins. */
export function rateInForce(versions: readonly CourierPayRateVersion[], date: string): CourierPayRateVersion | null {
  let best: CourierPayRateVersion | null = null;
  for (const version of versions) {
    if (version.effectiveFromDate > date) continue;
    if (
      best === null ||
      version.effectiveFromDate > best.effectiveFromDate ||
      (version.effectiveFromDate === best.effectiveFromDate && version.sequence > best.sequence)
    ) {
      best = version;
    }
  }
  return best;
}

/** Whole minutes worked (seconds dropped); never negative. */
export function shiftMinutes(startMillis: number, endMillis: number): number {
  return Math.max(0, Math.floor((endMillis - startMillis) / 60_000));
}

/** Minutes × hourly rate, per minute; rounded to the kuruş. */
export function shiftAmountMinorUnits(minutes: number, hourlyMinorUnits: number): number {
  return Math.round((minutes * hourlyMinorUnits) / 60);
}

export interface EarningLineSummary {
  kind: CourierEarningKind;
  quantity: number;
  amountMinorUnits: number;
}

export function summarizeEarnings(lines: readonly EarningLineSummary[]) {
  let packageCount = 0;
  let packageMinorUnits = 0;
  let shiftMinutesTotal = 0;
  let shiftMinorUnits = 0;
  for (const line of lines) {
    if (line.kind === "package") {
      packageCount += line.quantity;
      packageMinorUnits += line.amountMinorUnits;
    } else {
      shiftMinutesTotal += line.quantity;
      shiftMinorUnits += line.amountMinorUnits;
    }
  }
  return {
    packageCount,
    packageMinorUnits,
    shiftMinutes: shiftMinutesTotal,
    shiftMinorUnits,
    totalMinorUnits: packageMinorUnits + shiftMinorUnits,
  };
}

// ---------------------------------------------------------------------------
// Shared server helpers
// ---------------------------------------------------------------------------

export function courierPayProfileRef(db: Firestore, organizationId: string, staffUid: string) {
  return db.collection(COURIER_PAY_PROFILES_COLLECTION).doc(`${organizationId}_${staffUid}`);
}

function shiftPointerRef(db: Firestore, organizationId: string, staffUid: string) {
  return db.collection(COURIER_SHIFT_POINTERS_COLLECTION).doc(`${organizationId}_${staffUid}`);
}

function requireString(raw: unknown, field: string): string {
  if (typeof raw !== "string" || raw.trim().length === 0) invalid(`${field} is required.`);
  return (raw as string).trim();
}

export function optionalReason(raw: unknown): string {
  const reason = typeof raw === "string" ? raw.trim() : "";
  if (reason.length > MAX_REASON_LENGTH) invalid(`reason must be at most ${MAX_REASON_LENGTH} characters.`);
  return reason;
}

export function callerRoles(request: CallableRequest, organizationId: string): string[] | null {
  const roles = (request.auth?.token?.roles as Record<string, unknown> | undefined)?.[organizationId];
  return Array.isArray(roles) ? roles.filter((r): r is string => typeof r === "string") : null;
}

/** Only an admin/owner sets or changes a pool courier's rate. */
function assertMaySetKind(scope: StaffScope, kind: CourierPayKind, current: CourierPayRateVersion | null): void {
  if (scope.kind === "organization") return;
  if (kind === "pool" || current?.courierKind === "pool") {
    denied("Only an admin or owner can set a pool courier's pay.", "courierPay/pool-needs-admin");
  }
}

/**
 * Appends a rate version inside [tx] (the caller has already checked who
 * may set it). Reads the profile, so call it before the transaction's
 * first write.
 */
export async function appendCourierPayRate(params: {
  tx: Transaction;
  db: Firestore;
  organizationId: string;
  staffUid: string;
  branchIds: string[];
  input: CourierPayRateInput;
  effectiveFromDate: string;
  actorUid: string;
  actorRoles: string[] | null;
  now: Timestamp;
  scope: StaffScope;
  /** Stage 6A — set "Fatura Keser" with the first rate (staff form). */
  issuesInvoice?: boolean;
}): Promise<{ write: () => CourierPayRateVersion }> {
  const { tx, db, organizationId, staffUid, input, now } = params;
  const ref = courierPayProfileRef(db, organizationId, staffUid);
  const snap = await tx.get(ref);
  const existing = snap.exists ? (snap.data() as CourierPayProfileDoc) : null;
  const versions: CourierPayRateVersion[] = existing?.versions ?? [];
  const current = rateInForce(versions, istanbulDate(now.toMillis()));
  assertMaySetKind(params.scope, input.courierKind, current);
  return {
    write: () => {
      const sequence = versions.reduce((max, v) => Math.max(max, v.sequence), 0) + 1;
      const version: CourierPayRateVersion = {
        versionId: `v${sequence}`,
        sequence,
        courierKind: input.courierKind,
        perPackageMinorUnits: input.perPackageMinorUnits,
        hourlyMinorUnits: input.hourlyMinorUnits,
        currencyCode: "TRY",
        effectiveFromDate: params.effectiveFromDate,
        createdAt: now,
        createdByUid: params.actorUid,
      };
      // Stage 6A — keep the invoicing flag and the running totals.
      const doc: CourierPayProfileDoc = {
        ...(existing ?? {}),
        organizationId,
        staffUid,
        branchIds: params.branchIds,
        versions: [...versions, version],
        updatedAt: now,
        issuesInvoice: params.issuesInvoice ?? existing?.issuesInvoice ?? false,
      };
      tx.set(ref, doc);
      writeAuditEvent({
        tx, db, eventId: `${ref.id}-rate-${version.versionId}`, organizationId,
        type: "courierPay.rateSet", targetRef: ref.path,
        previousValue: current ? serializeVersion(current) : null,
        newValue: serializeVersion(version),
        actorType: "staff", actorUid: params.actorUid, actorRoles: params.actorRoles,
        correlationId: generateCorrelationId(), now,
      });
      return version;
    },
  };
}

function serializeVersion(version: CourierPayRateVersion) {
  return {
    versionId: version.versionId,
    courierKind: version.courierKind,
    perPackageMinorUnits: version.perPackageMinorUnits,
    hourlyMinorUnits: version.hourlyMinorUnits,
    currencyCode: version.currencyCode,
    effectiveFromDate: version.effectiveFromDate,
    createdAtMillis: version.createdAt.toMillis(),
  };
}

/** Validates the start date: today (Istanbul) at the earliest, at most a year ahead. */
export function resolveEffectiveFromDate(raw: unknown, nowMillis: number): string {
  const today = istanbulDate(nowMillis);
  if (raw === undefined || raw === null || raw === "") return today;
  if (!isValidDate(raw)) invalid("effectiveFromDate must be YYYY-MM-DD.", "courierPay/invalid-date");
  if (raw < today) invalid("A rate cannot start in the past.", "courierPay/backdated");
  if (daysBetween(today, raw) > MAX_EFFECTIVE_DAYS_AHEAD) invalid("A rate can start at most a year ahead.", "courierPay/invalid-date");
  return raw;
}

export async function loadCourierMembership(organizationId: string, staffUid: string): Promise<MembershipDoc> {
  const snap = await getFirestore().collection("memberships").doc(membershipId(organizationId, staffUid)).get();
  if (!snap.exists) throw new HttpsError("not-found", "No staff member found for this account in this organization.");
  const doc = snap.data() as MembershipDoc;
  if (!doc.roles.includes("courier")) precondition("This staff member is not a courier.", "courierPay/not-courier");
  return doc;
}

// ---------------------------------------------------------------------------
// Pay rates
// ---------------------------------------------------------------------------

/** "Kurye Ücreti" in the staff edit form: appends a new rate version. */
export const setCourierPayRate = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const targetUid = requireString(data.targetUid, "targetUid");
  if (targetUid === request.auth.uid) denied("Nobody sets their own pay.");
  const input = parseCourierPayRateInput(data);
  const nowMillis = Date.now();
  const effectiveFromDate = resolveEffectiveFromDate(data.effectiveFromDate, nowMillis);

  const scope = await resolveStaffScope(request, organizationId);
  const membership = await loadCourierMembership(organizationId, targetUid);
  assertTargetNotProtected(membership);
  assertWithinScope(scope, membership);

  const db = getFirestore();
  const now = Timestamp.fromMillis(nowMillis);
  const version = await db.runTransaction(async (tx) => {
    const pending = await appendCourierPayRate({
      tx, db, organizationId, staffUid: targetUid, branchIds: membership.branchAccess, input, effectiveFromDate,
      actorUid: request.auth!.uid, actorRoles: callerRoles(request, organizationId), now, scope,
    });
    return pending.write();
  });
  return { organizationId, targetUid, version: serializeVersion(version) };
});

/** The rate history and the rate in force, to prefill the staff edit form. */
export const getCourierPayProfile = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const targetUid = requireString(data.targetUid, "targetUid");
  const scope = await resolveStaffScope(request, organizationId);
  const membership = await loadCourierMembership(organizationId, targetUid);
  assertWithinScope(scope, membership);
  const snap = await courierPayProfileRef(getFirestore(), organizationId, targetUid).get();
  const versions = snap.exists ? ((snap.data() as CourierPayProfileDoc).versions ?? []) : [];
  const current = rateInForce(versions, istanbulDate(Date.now()));
  return {
    organizationId,
    targetUid,
    current: current ? serializeVersion(current) : null,
    versions: versions.map(serializeVersion),
    issuesInvoice: snap.exists ? (snap.data() as CourierPayProfileDoc).issuesInvoice === true : false,
  };
});

// ---------------------------------------------------------------------------
// Earnings lines written by other modules
// ---------------------------------------------------------------------------

/**
 * Package lines for a settlement: called by `settleCourierReturn` inside its
 * transaction. [profile] must have been read in the read phase.
 */
export function writePackageEarnings(params: {
  tx: Transaction;
  db: Firestore;
  profile: CourierPayProfileDoc | null;
  organizationId: string;
  branchId: string;
  courierId: string;
  courierName: string;
  orders: Array<{ orderId: string; orderNumber: string }>;
  now: Timestamp;
}): number {
  const { profile, now } = params;
  if (!profile) return 0;
  const earnedDate = istanbulDate(now.toMillis());
  const rate = rateInForce(profile.versions ?? [], earnedDate);
  if (!rate || rate.perPackageMinorUnits <= 0) return 0;
  for (const order of params.orders) {
    const line: CourierEarningDoc = {
      organizationId: params.organizationId,
      branchId: params.branchId,
      staffUid: profile.staffUid,
      courierId: params.courierId,
      courierName: params.courierName,
      kind: "package",
      sourceId: order.orderId,
      orderNumber: order.orderNumber,
      rateVersionId: rate.versionId,
      unitRateMinorUnits: rate.perPackageMinorUnits,
      quantity: 1,
      amountMinorUnits: rate.perPackageMinorUnits,
      currencyCode: rate.currencyCode,
      earnedAt: now,
      earnedDate,
      createdAt: now,
    };
    params.tx.set(params.db.collection(COURIER_EARNINGS_COLLECTION).doc(`pkg-${order.orderId}`), line);
  }
  params.tx.set(courierPayProfileRef(params.db, params.organizationId, profile.staffUid), {
    earnedTotalMinorUnits: FieldValue.increment(rate.perPackageMinorUnits * params.orders.length),
  }, { merge: true });
  return params.orders.length;
}

// ---------------------------------------------------------------------------
// Shifts — the courier's side
// ---------------------------------------------------------------------------

function serializeShift(id: string, shift: CourierShiftDoc) {
  const ms = (t: Timestamp | null) => (t ? t.toMillis() : null);
  return {
    shiftId: id,
    branchId: shift.branchId,
    staffUid: shift.staffUid,
    courierName: shift.courierName,
    status: shift.status,
    requestedStartAtMillis: ms(shift.requestedStartAt),
    approvedStartAtMillis: ms(shift.approvedStartAt),
    startAdjustReason: shift.startAdjustReason,
    requestedEndAtMillis: ms(shift.requestedEndAt),
    approvedEndAtMillis: ms(shift.approvedEndAt),
    endAdjustReason: shift.endAdjustReason,
    rejectReason: shift.rejectReason,
    approvedMinutes: shift.approvedMinutes,
    closedByManager: shift.closedByManager ?? false,
  };
}

/** "Vardiya Başlat" — a shop courier with an hourly rate asks to start a shift. */
export const courierStartShift = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { uid, account, courierId, courier } = await requireCourierAccount(request, tx, db);
    const organizationId = account.organizationId;
    if (courier.type === "pool") {
      denied("Shifts are for shop couriers only.", "courierShift/pool-courier");
    }
    const pointerRef = shiftPointerRef(db, organizationId, uid);
    const pointer = await tx.get(pointerRef);
    const profileSnap = await tx.get(courierPayProfileRef(db, organizationId, uid));
    const now = Timestamp.now();
    const rate = profileSnap.exists
      ? rateInForce((profileSnap.data() as CourierPayProfileDoc).versions ?? [], istanbulDate(now.toMillis()))
      : null;
    if (!rate || rate.courierKind !== "shop" || !rate.hourlyMinorUnits) {
      precondition("No hourly rate is set for this courier.", "courierShift/no-hourly-rate");
    }
    if (pointer.exists && typeof pointer.data()!.openShiftId === "string") {
      precondition("A shift is already open.", "courierShift/already-open");
    }
    const shiftRef = db.collection(COURIER_SHIFTS_COLLECTION).doc();
    const shift: CourierShiftDoc = {
      organizationId,
      branchId: String(courier.branchId ?? ""),
      staffUid: uid,
      courierId,
      courierName: String(courier.displayName ?? ""),
      status: "startRequested",
      requestedStartAt: now,
      approvedStartAt: null,
      startReviewedByUid: null,
      startAdjustReason: null,
      requestedEndAt: null,
      approvedEndAt: null,
      endReviewedByUid: null,
      endAdjustReason: null,
      rejectReason: null,
      approvedMinutes: null,
      earningLineId: null,
      createdAt: now,
      updatedAt: now,
    };
    tx.set(shiftRef, shift);
    tx.set(pointerRef, { organizationId, staffUid: uid, openShiftId: shiftRef.id, updatedAt: now });
    writeAuditEvent({
      tx, db, eventId: `courierShift-${shiftRef.id}-startRequested`, organizationId, branchId: shift.branchId,
      type: "courierShift.startRequested", targetRef: shiftRef.path,
      newValue: { requestedStartAtMillis: now.toMillis() },
      actorType: "courier", actorUid: uid, actorRoles: callerRoles(request, organizationId),
      correlationId: generateCorrelationId(), now,
    });
    return { shift: serializeShift(shiftRef.id, shift) };
  });
});

/** "Vardiya Bitir" — the courier asks to end its approved shift. */
export const courierEndShift = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const db = getFirestore();
  return db.runTransaction(async (tx) => {
    const { uid, account } = await requireCourierAccount(request, tx, db);
    const organizationId = account.organizationId;
    const pointer = await tx.get(shiftPointerRef(db, organizationId, uid));
    const openShiftId = pointer.exists ? pointer.data()!.openShiftId : null;
    if (typeof openShiftId !== "string") precondition("No shift is open.", "courierShift/none-open");
    const shiftRef = db.collection(COURIER_SHIFTS_COLLECTION).doc(openShiftId as string);
    const snap = await tx.get(shiftRef);
    if (!snap.exists) precondition("No shift is open.", "courierShift/none-open");
    const shift = snap.data() as CourierShiftDoc;
    if (shift.status === "startRequested") {
      precondition("The shift start is not approved yet.", "courierShift/start-not-approved");
    }
    if (shift.status !== "active") precondition("The end of this shift is already requested.", "courierShift/end-requested");
    const now = Timestamp.now();
    tx.update(shiftRef, { status: "endRequested", requestedEndAt: now, updatedAt: now });
    writeAuditEvent({
      tx, db, eventId: `courierShift-${shiftRef.id}-endRequested`, organizationId, branchId: shift.branchId,
      type: "courierShift.endRequested", targetRef: shiftRef.path,
      newValue: { requestedEndAtMillis: now.toMillis() },
      actorType: "courier", actorUid: uid, actorRoles: callerRoles(request, organizationId),
      correlationId: generateCorrelationId(), now,
    });
    return { shift: serializeShift(shiftRef.id, { ...shift, status: "endRequested", requestedEndAt: now, updatedAt: now }) };
  });
});

// ---------------------------------------------------------------------------
// Shifts — the manager's side
// ---------------------------------------------------------------------------

function inScope(scope: StaffScope, branchId: string): boolean {
  return scope.kind === "organization" || scope.branches.has(branchId);
}

/** Open shifts (waiting for a start/end approval, or running) in the caller's branches. */
export const listCourierShifts = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const scope = await resolveStaffScope(request, organizationId);
  const snap = await getFirestore()
    .collection(COURIER_SHIFTS_COLLECTION)
    .where("organizationId", "==", organizationId)
    .where("status", "in", ["startRequested", "active", "endRequested"])
    .get();
  const shifts = snap.docs
    .map((doc) => ({ id: doc.id, shift: doc.data() as CourierShiftDoc }))
    .filter(({ shift }) => inScope(scope, shift.branchId))
    .sort((a, b) => a.shift.requestedStartAt.toMillis() - b.shift.requestedStartAt.toMillis())
    .map(({ id, shift }) => serializeShift(id, shift));
  return { organizationId, shifts };
});

function resolveApprovedTime(raw: unknown, requested: Timestamp, nowMillis: number): Timestamp {
  if (raw === undefined || raw === null) return requested;
  if (typeof raw !== "number" || !Number.isInteger(raw)) invalid("approvedAtMillis must be a timestamp in milliseconds.");
  const millis = raw as number;
  if (millis > nowMillis) invalid("An approved time cannot be in the future.", "courierShift/future-time");
  if (Math.abs(millis - requested.toMillis()) > MAX_ADJUST_MS) {
    invalid("A corrected time must be within 12 hours of the pressed time.", "courierShift/adjust-too-far");
  }
  return Timestamp.fromMillis(millis);
}

/**
 * The manager's answer to a start or end request: `approve` (optionally
 * with a corrected time — then a reason is required) or, for a start only,
 * `reject`. Approving the end closes the shift and writes its earning line.
 * `close` ends a running shift the courier forgot to end: the manager gives
 * the end time and a reason (stage 5 follow-up).
 */
export const reviewCourierShift = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const shiftId = requireString(data.shiftId, "shiftId");
  const decision = data.decision;
  if (decision !== "approve" && decision !== "reject" && decision !== "close") {
    invalid('decision must be "approve", "reject" or "close".');
  }
  const reason = optionalReason(data.reason);
  const scope = await resolveStaffScope(request, organizationId);
  const actorUid = request.auth.uid;
  const actorRoles = callerRoles(request, organizationId);
  const db = getFirestore();
  const shiftRef = db.collection(COURIER_SHIFTS_COLLECTION).doc(shiftId);

  return db.runTransaction(async (tx) => {
    const snap = await tx.get(shiftRef);
    if (!snap.exists) throw new HttpsError("not-found", "Shift not found.");
    const shift = snap.data() as CourierShiftDoc;
    if (shift.organizationId !== organizationId || !inScope(scope, shift.branchId)) {
      throw new HttpsError("not-found", "Shift not found.");
    }
    if (shift.staffUid === actorUid) denied("Nobody approves their own shift.");
    const pointerRef = shiftPointerRef(db, organizationId, shift.staffUid);
    const profileSnap = await tx.get(courierPayProfileRef(db, organizationId, shift.staffUid));
    const nowMillis = Date.now();
    const now = Timestamp.fromMillis(nowMillis);
    const audit = (type: string, newValue: Record<string, unknown>, reasonMessage: string | null) =>
      writeAuditEvent({
        tx, db, eventId: `courierShift-${shiftId}-${type.split(".")[1]}`, organizationId, branchId: shift.branchId,
        type, targetRef: shiftRef.path, newValue, reasonMessage,
        actorType: "staff", actorUid, actorRoles, correlationId: generateCorrelationId(), now,
      });

    if (decision === "close" && shift.status !== "active") {
      precondition("Only a running shift can be ended by a manager.", "courierShift/not-running");
    }
    if (decision !== "close" && shift.status === "active") {
      precondition(`This shift is "${shift.status}" and waits for no approval.`, "courierShift/not-pending");
    }

    if (shift.status === "startRequested") {
      if (decision === "reject") {
        tx.update(shiftRef, { status: "rejected", rejectReason: reason || null, startReviewedByUid: actorUid, updatedAt: now });
        tx.delete(pointerRef);
        audit("courierShift.startRejected", {}, reason || null);
        return { shift: serializeShift(shiftId, { ...shift, status: "rejected", rejectReason: reason || null }) };
      }
      const approvedStartAt = resolveApprovedTime(data.approvedAtMillis, shift.requestedStartAt, nowMillis);
      const adjusted = approvedStartAt.toMillis() !== shift.requestedStartAt.toMillis();
      if (adjusted && reason.length === 0) invalid("A reason is required when the time is corrected.", "courierShift/reason-required");
      const update = {
        status: "active" as const, approvedStartAt, startReviewedByUid: actorUid,
        startAdjustReason: adjusted ? reason : null, updatedAt: now,
      };
      tx.update(shiftRef, update);
      audit("courierShift.startApproved", { approvedStartAtMillis: approvedStartAt.toMillis(), adjusted }, adjusted ? reason : null);
      return { shift: serializeShift(shiftId, { ...shift, ...update }) };
    }

    if (shift.status === "endRequested" || shift.status === "active") {
      if (decision === "reject") {
        invalid("The end of a shift cannot be rejected; correct the time instead.", "courierShift/end-not-rejectable");
      }
      const startMillis = shift.approvedStartAt!.toMillis();
      const closedByManager = shift.status === "active";
      let approvedEndAt: Timestamp;
      let adjusted: boolean;
      if (closedByManager) {
        // The courier never pressed "Vardiya Bitir": the manager states when it ended.
        const raw = data.approvedAtMillis;
        if (typeof raw !== "number" || !Number.isInteger(raw)) {
          invalid("approvedAtMillis is required to end a running shift.", "courierShift/end-time-required");
        }
        if ((raw as number) > nowMillis) invalid("An approved time cannot be in the future.", "courierShift/future-time");
        if ((raw as number) - startMillis > MAX_SHIFT_MS) {
          invalid("A shift can last at most 24 hours.", "courierShift/too-long");
        }
        if (reason.length === 0) invalid("A reason is required to end a shift for the courier.", "courierShift/reason-required");
        approvedEndAt = Timestamp.fromMillis(raw as number);
        adjusted = true;
      } else {
        const requestedEndAt = shift.requestedEndAt!;
        approvedEndAt = resolveApprovedTime(data.approvedAtMillis, requestedEndAt, nowMillis);
        adjusted = approvedEndAt.toMillis() !== requestedEndAt.toMillis();
        if (adjusted && reason.length === 0) invalid("A reason is required when the time is corrected.", "courierShift/reason-required");
      }
      if (approvedEndAt.toMillis() <= startMillis) invalid("The end must be after the start.", "courierShift/end-before-start");
      // The hourly rate in force on the shift's (approved) start date.
      const rate = profileSnap.exists
        ? rateInForce((profileSnap.data() as CourierPayProfileDoc).versions ?? [], istanbulDate(startMillis))
        : null;
      if (!rate || !rate.hourlyMinorUnits) precondition("No hourly rate is set for this courier.", "courierShift/no-hourly-rate");
      const minutes = shiftMinutes(startMillis, approvedEndAt.toMillis());
      const lineId = `shift-${shiftId}`;
      const line: CourierEarningDoc = {
        organizationId,
        branchId: shift.branchId,
        staffUid: shift.staffUid,
        courierId: shift.courierId,
        courierName: shift.courierName,
        kind: "shift",
        sourceId: shiftId,
        orderNumber: null,
        rateVersionId: rate!.versionId,
        unitRateMinorUnits: rate!.hourlyMinorUnits!,
        quantity: minutes,
        amountMinorUnits: shiftAmountMinorUnits(minutes, rate!.hourlyMinorUnits!),
        currencyCode: rate!.currencyCode,
        earnedAt: approvedEndAt,
        earnedDate: istanbulDate(startMillis),
        createdAt: now,
      };
      tx.set(db.collection(COURIER_EARNINGS_COLLECTION).doc(lineId), line);
      tx.set(courierPayProfileRef(db, organizationId, shift.staffUid), {
        earnedTotalMinorUnits: FieldValue.increment(line.amountMinorUnits),
      }, { merge: true });
      const update = {
        status: "closed" as const, approvedEndAt, endReviewedByUid: actorUid,
        endAdjustReason: adjusted ? reason : null, approvedMinutes: minutes, earningLineId: lineId,
        closedByManager, updatedAt: now,
      };
      tx.update(shiftRef, update);
      tx.delete(pointerRef);
      audit(closedByManager ? "courierShift.closedByManager" : "courierShift.endApproved", {
        approvedEndAtMillis: approvedEndAt.toMillis(), adjusted, approvedMinutes: minutes, amountMinorUnits: line.amountMinorUnits,
      }, adjusted ? reason : null);
      return { shift: serializeShift(shiftId, { ...shift, ...update }) };
    }

    precondition(`This shift is "${shift.status}" and waits for no approval.`, "courierShift/not-pending");
  });
});

// ---------------------------------------------------------------------------
// Earnings views
// ---------------------------------------------------------------------------

export function requirePeriod(data: Record<string, unknown>): { fromDate: string; toDate: string } {
  const fromDate = data.fromDate;
  const toDate = data.toDate;
  if (!isValidDate(fromDate) || !isValidDate(toDate)) invalid("fromDate and toDate must be YYYY-MM-DD.");
  if (toDate < fromDate) invalid("toDate must not be before fromDate.");
  if (daysBetween(fromDate, toDate) > MAX_PERIOD_DAYS) invalid(`A period is at most ${MAX_PERIOD_DAYS} days.`);
  return { fromDate, toDate };
}

function serializeLine(id: string, line: CourierEarningDoc) {
  return {
    lineId: id,
    branchId: line.branchId,
    staffUid: line.staffUid,
    courierName: line.courierName,
    kind: line.kind,
    sourceId: line.sourceId,
    orderNumber: line.orderNumber,
    unitRateMinorUnits: line.unitRateMinorUnits,
    quantity: line.quantity,
    amountMinorUnits: line.amountMinorUnits,
    earnedAtMillis: line.earnedAt.toMillis(),
    earnedDate: line.earnedDate,
  };
}

type SerializedLine = ReturnType<typeof serializeLine>;

function groupByCourier(lines: SerializedLine[]) {
  const byCourier = new Map<string, SerializedLine[]>();
  for (const line of lines) {
    const list = byCourier.get(line.staffUid) ?? [];
    list.push(line);
    byCourier.set(line.staffUid, list);
  }
  return [...byCourier.entries()]
    .map(([staffUid, courierLines]) => {
      courierLines.sort((a, b) => b.earnedAtMillis - a.earnedAtMillis);
      return {
        staffUid,
        courierName: courierLines[0]?.courierName ?? "",
        ...summarizeEarnings(courierLines),
        lines: courierLines,
      };
    })
    .sort((a, b) => a.courierName.localeCompare(b.courierName, "tr"));
}

/** Manager/admin view: earnings per courier for a period, in the caller's branches. */
export const getCourierEarnings = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "Sign-in is required.");
  const data = (request.data ?? {}) as Record<string, unknown>;
  const organizationId = requireString(data.organizationId, "organizationId");
  const { fromDate, toDate } = requirePeriod(data);
  const scope = await resolveStaffScope(request, organizationId);
  const db = getFirestore();
  const snap = await db
    .collection(COURIER_EARNINGS_COLLECTION)
    .where("organizationId", "==", organizationId)
    .where("earnedDate", ">=", fromDate)
    .where("earnedDate", "<=", toDate)
    .limit(MAX_EARNING_LINES)
    .get();
  const lines = snap.docs
    .map((doc) => ({ id: doc.id, line: doc.data() as CourierEarningDoc }))
    .filter(({ line }) => inScope(scope, line.branchId))
    .map(({ id, line }) => serializeLine(id, line));
  // Stage 6A — payments in the period (by payment date), in the caller's branches.
  const paymentSnap = await db.collection(COURIER_PAYMENTS_COLLECTION).where("organizationId", "==", organizationId).get();
  const payments = paymentSnap.docs
    .map((doc) => ({ id: doc.id, payment: doc.data() as CourierPaymentDoc }))
    .filter(({ payment }) => payment.paidDate >= fromDate && payment.paidDate <= toDate)
    .filter(({ payment }) => scope.kind === "organization" || payment.branchIds.some((b) => scope.branches.has(b)));
  const grouped = groupByCourier(lines);
  const names = new Map<string, string>();
  for (const c of grouped) names.set(c.staffUid, c.courierName);
  for (const { payment } of payments) if (!names.has(payment.staffUid)) names.set(payment.staffUid, payment.courierName);
  const profileRefs = [...names.keys()].map((uid) => courierPayProfileRef(db, organizationId, uid));
  const profiles = profileRefs.length > 0 ? await db.getAll(...profileRefs) : [];
  const profileByUid = new Map(
    profiles.map((p) => [p.id.slice(organizationId.length + 1), p.exists ? (p.data() as CourierPayProfileDoc) : null]),
  );
  const empty = summarizeEarnings([]);
  const couriers = [...names.entries()]
    .map(([staffUid, courierName]) => {
      const entry = grouped.find((c) => c.staffUid === staffUid) ?? { staffUid, courierName, ...empty, lines: [] };
      const own = payments.filter(({ payment }) => payment.staffUid === staffUid);
      const profile = profileByUid.get(staffUid) ?? null;
      return {
        ...entry,
        issuesInvoice: profile?.issuesInvoice === true,
        paidInPeriodMinorUnits: own.reduce((sum, { payment }) => sum + payment.amountMinorUnits, 0),
        payments: own.map(({ id, payment }) => serializePayment(id, payment)).sort((a, b) => b.createdAtMillis - a.createdAtMillis),
        ...balanceOf(profile),
      };
    })
    .sort((a, b) => a.courierName.localeCompare(b.courierName, "tr"));
  return {
    organizationId,
    fromDate,
    toDate,
    totalMinorUnits: couriers.reduce((sum, c) => sum + c.totalMinorUnits, 0),
    paidInPeriodMinorUnits: couriers.reduce((sum, c) => sum + c.paidInPeriodMinorUnits, 0),
    /** Stage 6A — money out is admin/owner only. */
    canRecordPayments: scope.kind === "organization",
    truncated: snap.size >= MAX_EARNING_LINES,
    couriers,
  };
});

/** The courier app's "Kazancım": own earnings for a period, the rate in force, the open shift, payments and invoices. */
export const getMyCourierPay = onCall({ enforceAppCheck: shouldEnforceAppCheck() }, async (request: CallableRequest) => {
  const data = (request.data ?? {}) as Record<string, unknown>;
  const { fromDate, toDate } = requirePeriod(data);
  const db = getFirestore();
  const context = await db.runTransaction(async (tx) => {
    const { uid, account, courier } = await requireCourierAccount(request, tx, db);
    const organizationId = account.organizationId;
    const profileSnap = await tx.get(courierPayProfileRef(db, organizationId, uid));
    const pointer = await tx.get(shiftPointerRef(db, organizationId, uid));
    const openShiftId = pointer.exists ? pointer.data()!.openShiftId : null;
    const shiftSnap = typeof openShiftId === "string"
      ? await tx.get(db.collection(COURIER_SHIFTS_COLLECTION).doc(openShiftId))
      : null;
    return { uid, organizationId, courier: courier as DocumentData, profileSnap, shiftSnap };
  });
  const { uid, organizationId, profileSnap, shiftSnap } = context;
  const profile = profileSnap.exists ? (profileSnap.data() as CourierPayProfileDoc) : null;
  const current = rateInForce(profile?.versions ?? [], istanbulDate(Date.now()));
  const snap = await db
    .collection(COURIER_EARNINGS_COLLECTION)
    .where("staffUid", "==", uid)
    .where("earnedDate", ">=", fromDate)
    .where("earnedDate", "<=", toDate)
    .limit(MAX_EARNING_LINES)
    .get();
  const lines = snap.docs
    .map((doc) => ({ id: doc.id, line: doc.data() as CourierEarningDoc }))
    .filter(({ line }) => line.organizationId === organizationId)
    .map(({ id, line }) => serializeLine(id, line))
    .sort((a, b) => b.earnedAtMillis - a.earnedAtMillis);
  const paymentSnap = await db.collection(COURIER_PAYMENTS_COLLECTION).where("staffUid", "==", uid).get();
  const payments = paymentSnap.docs
    .map((doc) => ({ id: doc.id, payment: doc.data() as CourierPaymentDoc }))
    .filter(({ payment }) => payment.organizationId === organizationId);
  const inPeriod = payments.filter(({ payment }) => payment.paidDate >= fromDate && payment.paidDate <= toDate);
  const invoiceSnap = await db.collection(COURIER_INVOICES_COLLECTION).where("staffUid", "==", uid).get();
  const invoices = invoiceSnap.docs
    .map((doc) => ({ id: doc.id, invoice: doc.data() as CourierInvoiceDoc }))
    .filter(({ invoice }) => invoice.organizationId === organizationId)
    .map(({ id, invoice }) => serializeInvoice(id, invoice))
    .sort((a, b) => b.createdAtMillis - a.createdAtMillis)
    .slice(0, 50);
  return {
    organizationId,
    fromDate,
    toDate,
    shiftsEnabled: context.courier.type !== "pool",
    issuesInvoice: profile?.issuesInvoice === true,
    currentRate: current ? serializeVersion(current) : null,
    openShift: shiftSnap?.exists ? serializeShift(shiftSnap.id, shiftSnap.data() as CourierShiftDoc) : null,
    ...summarizeEarnings(lines),
    lines,
    paidInPeriodMinorUnits: inPeriod.reduce((sum, { payment }) => sum + payment.amountMinorUnits, 0),
    payments: inPeriod.map(({ id, payment }) => serializePayment(id, payment)).sort((a, b) => b.createdAtMillis - a.createdAtMillis),
    ...balanceOf(profile),
    invoices,
  };
});
