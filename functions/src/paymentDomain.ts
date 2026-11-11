import type { Timestamp } from "firebase-admin/firestore";
import { DELIVERY_PAYMENT_METHOD_CATALOG } from "./deliveryPaymentMethodCatalog";

/**
 * AP-4 Wave A — canonical payment/tender/refund domain contracts. No
 * Firestore I/O lives here — mirrors `checkAllocationConfig.ts`'s own
 * "policy/vocabulary only" shape and this codebase's established
 * flat-top-level-collection convention (never a subcollection).
 *
 * Builds directly on top of AP-3's real `checks`/`checkAllocations`
 * (`checkAllocationConfig.ts`) — this file introduces no parallel
 * basket/order-total/split-account model. A `PaymentIntent` is a frozen,
 * re-verifiable snapshot of what AP-3's own `checkAllocations` say is
 * payable, per sub-account, at the moment it was captured; nothing here
 * ever recomputes a total independently of `checkAllocations`.
 *
 * State machines below are locked to `docs/payment_cash_fiscal_architecture
 * .md` §8 exactly (state names chosen to match this codebase's existing
 * camelCase convention rather than the doc's SCREAMING_CASE prose).
 */

export const PAYMENT_INTENTS_COLLECTION = "paymentIntents";
export const PAYMENT_SESSIONS_COLLECTION = "paymentSessions";
export const PAYMENT_ATTEMPTS_COLLECTION = "paymentAttempts";
export const REFUND_REQUESTS_COLLECTION = "refundRequests";
export const BRANCH_PAYMENT_CONFIG_COLLECTION = "branchPaymentConfig";

// ---------------------------------------------------------------------
// Tender types
// ---------------------------------------------------------------------

/**
 * Campaign/manual discount are price ADJUSTMENTS (already resolved into
 * `checkAllocations`' amounts before a `PaymentIntent` is ever captured),
 * never a tender type — per the governing instruction's explicit
 * distinction. `boncuk` wraps the existing, real, already-CLOSED loyalty
 * ledger mechanism (`loyaltyLedger.ts`) unchanged — no new Boncuk logic,
 * only a new way to spend it.
 */
export const TENDER_TYPES = ["cash", "card", "mealCard", "boncuk"] as const;
export type TenderType = (typeof TENDER_TYPES)[number];

export function sanitizeTenderType(raw: unknown): TenderType {
  if (typeof raw !== "string" || !(TENDER_TYPES as readonly string[]).includes(raw)) {
    throw new Error(`tenderType must be one of: ${TENDER_TYPES.join(", ")}.`);
  }
  return raw as TenderType;
}

// ---------------------------------------------------------------------
// External-terminal capture (2026-11-11, product owner decision)
// ---------------------------------------------------------------------

/**
 * Card and meal-card payments are taken on the bank's / the meal-card
 * provider's own physical terminal; the cashier then records the result on
 * the POS. Such an attempt settles immediately (like cash) — there is no
 * integrated provider round-trip. The provider-adapter path stays for any
 * caller that does not ask for this capture mode.
 */
export const EXTERNAL_TERMINAL_CAPTURE_MODE = "externalTerminal";
export type PaymentCaptureMode = typeof EXTERNAL_TERMINAL_CAPTURE_MODE;

export const EXTERNAL_SLIP_NUMBER_MAX_LENGTH = 64;

const CARD_DISPLAY_NAME = "Kredi/Banka Kartı";

export type ExternalTerminalTender =
  | { status: "ok"; paymentMethodId: string | null; paymentMethodDisplayName: string; externalSlipNumber: string | null }
  | { status: "invalid"; message: string };

/**
 * Validates an external-terminal tender: only `card`/`mealCard`; a meal card
 * must name its brand — a `mealCard` entry of the payment-method catalog
 * (Pluxee, Multinet, Setcard, Edenred, ...) — so the Z report and the
 * payment history can tell the brands apart; the optional slip number is
 * trimmed and length-capped.
 */
export function resolveExternalTerminalTender(
  tenderType: TenderType,
  rawPaymentMethodId: unknown,
  rawSlipNumber: unknown,
): ExternalTerminalTender {
  if (tenderType !== "card" && tenderType !== "mealCard") {
    return { status: "invalid", message: "Only card and meal-card tenders may be recorded from an external terminal." };
  }
  let externalSlipNumber: string | null = null;
  if (rawSlipNumber !== undefined && rawSlipNumber !== null) {
    if (typeof rawSlipNumber !== "string") return { status: "invalid", message: "externalSlipNumber must be a string." };
    const trimmed = rawSlipNumber.trim();
    if (trimmed.length > EXTERNAL_SLIP_NUMBER_MAX_LENGTH) {
      return { status: "invalid", message: `externalSlipNumber must be at most ${EXTERNAL_SLIP_NUMBER_MAX_LENGTH} characters.` };
    }
    externalSlipNumber = trimmed.length > 0 ? trimmed : null;
  }
  if (tenderType === "card") {
    if (rawPaymentMethodId !== undefined && rawPaymentMethodId !== null) {
      return { status: "invalid", message: "A card tender takes no paymentMethodId." };
    }
    return { status: "ok", paymentMethodId: null, paymentMethodDisplayName: CARD_DISPLAY_NAME, externalSlipNumber };
  }
  const method = typeof rawPaymentMethodId === "string" ? DELIVERY_PAYMENT_METHOD_CATALOG[rawPaymentMethodId] : undefined;
  if (!method || method.reportingCategory !== "mealCard") {
    return { status: "invalid", message: "A meal-card tender must name a meal-card brand (paymentMethodId)." };
  }
  return { status: "ok", paymentMethodId: method.id, paymentMethodDisplayName: method.displayName, externalSlipNumber };
}

// ---------------------------------------------------------------------
// PaymentSession — one per Check, at most one non-terminal at a time
// ---------------------------------------------------------------------

export type PaymentSessionStatus =
  | "collecting"
  | "readyToComplete"
  | "completing"
  | "completed"
  | "cancelled"
  | "failed";

const PAYMENT_SESSION_TRANSITIONS: Readonly<Record<PaymentSessionStatus, readonly PaymentSessionStatus[]>> = {
  collecting: ["readyToComplete", "cancelled"],
  readyToComplete: ["collecting", "cancelled", "completing"],
  completing: ["completed", "failed"],
  completed: [],
  cancelled: [],
  failed: ["completing", "collecting"],
};

export function canTransitionPaymentSession(from: PaymentSessionStatus, to: PaymentSessionStatus): boolean {
  return PAYMENT_SESSION_TRANSITIONS[from].includes(to);
}

/**
 * A session never jumps straight from `collecting` to `completed` — the
 * locked state machine requires `collecting -> readyToComplete ->
 * completing -> completed`. When full settlement is detected, this walks
 * that exact chain (server-rejecting, returning `null`, if any hop from the
 * session's CURRENT status isn't a valid transition — e.g. an already-
 * `cancelled`/`failed` session never silently completes) rather than
 * asserting a shortcut the transition table doesn't itself allow.
 */
const COMPLETION_CHAIN_FROM: Readonly<Partial<Record<PaymentSessionStatus, readonly PaymentSessionStatus[]>>> = {
  collecting: ["readyToComplete", "completing", "completed"],
  readyToComplete: ["completing", "completed"],
  completing: ["completed"],
  completed: [],
};

export function computeCompletedSessionStatus(from: PaymentSessionStatus): PaymentSessionStatus | null {
  if (from === "completed") return "completed";
  const chain = COMPLETION_CHAIN_FROM[from];
  if (!chain) return null;
  let current: PaymentSessionStatus = from;
  for (const next of chain) {
    if (!canTransitionPaymentSession(current, next)) return null;
    current = next;
  }
  return current;
}

export interface PaymentSessionDoc {
  organizationId: string;
  branchId: string;
  checkId: string;
  intentId: string;
  status: PaymentSessionStatus;
  payableAmountMinorUnits: number; // frozen snapshot at intent-capture time
  settledAmountMinorUnits: number; // sum of succeeded attempts' allocations, kept current
  currencyCode: string;
  cashTipMinorUnits: number;
  cardTipMinorUnits: number;
  createdAt: Timestamp;
  createdByStaffUid: string;
  updatedAt: Timestamp;
  version: number;
}

// ---------------------------------------------------------------------
// PaymentIntent — a frozen, re-verifiable snapshot of what's payable
// ---------------------------------------------------------------------

export interface PaymentIntentAllocationSnapshot {
  subAccountId: string;
  payableAmountMinorUnits: number; // sum of that sub-account's active checkAllocations at capture time
}

export interface PaymentIntentDoc {
  organizationId: string;
  branchId: string;
  checkId: string;
  checkVersionAtCapture: number; // CheckDoc.version this intent was computed from — staleness check key
  subAccountAllocations: PaymentIntentAllocationSnapshot[];
  payableAmountMinorUnits: number; // sum of subAccountAllocations
  serviceCharges: ServiceChargeSnapshot[];
  currencyCode: string;
  createdAt: Timestamp;
  createdByStaffUid: string;
  supersededAt: Timestamp | null; // set once the underlying Check changes past this intent's capture
}

// ---------------------------------------------------------------------
// Cover / service charge — branch-authoritative, computed server-side only
// ---------------------------------------------------------------------

export type ServiceChargeType = "cover" | "service";
export type ServiceChargeBasis = "flat" | "percentage" | "perPerson";

export interface ServiceChargeSnapshot {
  type: ServiceChargeType;
  basis: ServiceChargeBasis;
  amountMinorUnits: number; // resolved amount actually applied, frozen
}

export interface BranchPaymentConfigDoc {
  organizationId: string;
  branchId: string;
  coverCharge: { enabled: boolean; basis: ServiceChargeBasis; amountMinorUnits: number; discountable: boolean } | null;
  serviceCharge: { enabled: boolean; basis: ServiceChargeBasis; amountMinorUnits: number; discountable: boolean } | null;
  cashRegisterModel: "sharedDrawer" | "cashierBound";
  showExpectedCashBeforeCount: boolean;
  refundWindowDays: number | null; // branch policy may only TIGHTEN provider/legal limits, never loosen
  businessDayCutoverHour: number; // 0-23, local branch timezone; branch-configurable after-midnight cutover
  timezone: string; // IANA timezone id, e.g. "Europe/Istanbul"
  updatedAt: Timestamp;
  version: number;
}

/** Pure, deterministic — computes the resolved cover/service charge amount for one Check's base subtotal, given branch policy. Never called from the client. */
export function computeServiceCharges(params: {
  config: BranchPaymentConfigDoc | null;
  baseSubtotalMinorUnits: number;
  coverCount: number;
}): ServiceChargeSnapshot[] {
  const { config, baseSubtotalMinorUnits, coverCount } = params;
  if (!config) return [];
  const charges: ServiceChargeSnapshot[] = [];
  for (const [type, charge] of [
    ["cover", config.coverCharge],
    ["service", config.serviceCharge],
  ] as const) {
    if (!charge || !charge.enabled) continue;
    let amountMinorUnits: number;
    switch (charge.basis) {
      case "flat":
        amountMinorUnits = charge.amountMinorUnits;
        break;
      case "perPerson":
        amountMinorUnits = charge.amountMinorUnits * Math.max(coverCount, 0);
        break;
      case "percentage":
        amountMinorUnits = Math.round((baseSubtotalMinorUnits * charge.amountMinorUnits) / 10_000);
        break;
    }
    if (amountMinorUnits > 0) charges.push({ type, basis: charge.basis, amountMinorUnits });
  }
  return charges;
}

// ---------------------------------------------------------------------
// PaymentAttempt — one immutable record per tender action
// ---------------------------------------------------------------------

/**
 * Locked to Doc C §8 exactly. `succeeded`/`declined` are direct terminal
 * provider outcomes; `timedOut` is the ONLY state that ever detours through
 * `unknownReconciliationRequired` before reaching a `resolved*` terminal —
 * a definitive provider answer is never second-guessed into "unknown."
 * `reversed` only ever follows `succeeded` (a void before settlement).
 */
export type PaymentAttemptStatus =
  | "initiated"
  | "providerPending"
  | "succeeded"
  | "declined"
  | "timedOut"
  | "unknownReconciliationRequired"
  | "resolvedSucceeded"
  | "resolvedFailed"
  | "reversed";

const PAYMENT_ATTEMPT_TRANSITIONS: Readonly<Record<PaymentAttemptStatus, readonly PaymentAttemptStatus[]>> = {
  initiated: ["providerPending", "succeeded", "declined"], // boncuk/cash resolve synchronously, skipping providerPending
  providerPending: ["succeeded", "declined", "timedOut"],
  succeeded: ["reversed"],
  declined: [],
  timedOut: ["unknownReconciliationRequired"],
  unknownReconciliationRequired: ["resolvedSucceeded", "resolvedFailed"],
  resolvedSucceeded: ["reversed"],
  resolvedFailed: [],
  reversed: [],
};

export function canTransitionPaymentAttempt(from: PaymentAttemptStatus, to: PaymentAttemptStatus): boolean {
  return PAYMENT_ATTEMPT_TRANSITIONS[from].includes(to);
}

/** Whether an attempt in [status] counts toward `PaymentSessionDoc.settledAmountMinorUnits` — i.e. money genuinely, currently collected. */
export function isAttemptSettled(status: PaymentAttemptStatus): boolean {
  return status === "succeeded" || status === "resolvedSucceeded";
}

export interface PaymentAllocationEntry {
  subAccountId: string;
  orderLineRefs: string[]; // `${sourceOrderId}_${sourceLineIndex}` — mirrors orderLineAllocationLedgerId's own key shape, informational/traceability only here
  amountMinorUnits: number;
}

export interface PaymentAttemptDoc {
  organizationId: string;
  branchId: string;
  checkId: string;
  sessionId: string;
  intentId: string;
  tenderType: TenderType;
  status: PaymentAttemptStatus;
  amountMinorUnits: number; // == sum(allocations[].amountMinorUnits)
  currencyCode: string;
  allocations: PaymentAllocationEntry[];
  idempotencyKey: string; // client-supplied, unique per attempt — a retry with the SAME key returns the original result, never a new attempt
  providerRef: string | null;
  providerResponseSummary: string | null; // never raw PAN/CVV/PIN/OTP — see C2's persistence ban
  loyaltyLedgerEntryId: string | null; // set only for tenderType:"boncuk" once committed
  declineReason: string | null;
  createdAt: Timestamp;
  createdByStaffUid: string;
  resolvedAt: Timestamp | null;
  correlationId: string;
  /**
   * AP-4 Wave B — set only for `tenderType:"cash"` when the cashier's
   * client supplied one; drives a linked `cashMovements` (`cashSale`) doc.
   * Optional this wave (a cash attempt with no drawer session still
   * settles exactly as it did in Wave A) — real, tested, but not yet
   * mandatorily enforced; see ADR-045.
   */
  cashSessionId: string | null;
  /**
   * 2026-11-11 — set to `"externalTerminal"` when a card/meal-card payment
   * was taken on a physical bank / provider terminal and only recorded here
   * (settled immediately). Absent on older attempts and other tenders.
   */
  captureMode?: PaymentCaptureMode | null;
  /** Meal-card brand (`DELIVERY_PAYMENT_METHOD_CATALOG` id, e.g. "multinet"). */
  paymentMethodId?: string | null;
  /** Shown in the payment history and the Z report ("Multinet"). */
  paymentMethodDisplayName?: string | null;
  /** Optional slip / provision number from the external terminal. */
  externalSlipNumber?: string | null;
}

// ---------------------------------------------------------------------
// RefundRequest — per-allocation sub-status, never a single flat boolean
// ---------------------------------------------------------------------

export type RefundType = "full" | "partial";
export type RefundAllocationStatus =
  | "providerPending"
  | "succeeded"
  | "failed"
  | "unknownReconciliationRequired"
  | "resolvedSucceeded"
  | "resolvedFailed";

export type RefundStatus =
  | "requested"
  | "pendingApproval"
  | "providerPending"
  | "partiallySucceeded"
  | "succeeded"
  | "failed"
  | "rejected"
  | "unknownReconciliationRequired"
  | "resolved";

export interface RefundAllocationEntry {
  originalAttemptId: string;
  tenderType: TenderType;
  amountMinorUnits: number; // this instrument's apportioned share, largest-remainder rounding
  status: RefundAllocationStatus;
  providerRef: string | null;
  cashMovementId: string | null; // set only for tenderType:"cash" once a real CashMovement is written (Wave B)
  loyaltyLedgerEntryId: string | null; // set only for tenderType:"boncuk" once restored
}

export interface RefundRequestDoc {
  organizationId: string;
  branchId: string;
  checkId: string;
  refundType: RefundType;
  orderLineRefs: string[] | null; // set for partial/item-level refunds, null for full
  amountMinorUnits: number; // == sum(allocations[].amountMinorUnits)
  allocations: RefundAllocationEntry[];
  status: RefundStatus;
  reasonCode: string;
  reasonMessage: string;
  requestedByStaffUid: string;
  approvalRequestRef: string | null;
  createdAt: Timestamp;
  resolvedAt: Timestamp | null;
  version: number;
}
