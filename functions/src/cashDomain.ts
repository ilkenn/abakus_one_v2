import type { Timestamp } from "firebase-admin/firestore";

/**
 * AP-4 Wave B — canonical cash register / business-day domain contracts. No
 * Firestore I/O lives here — mirrors `paymentDomain.ts`'s own "policy/
 * vocabulary only" shape.
 *
 * Ports the existing, business-rule-locked Flutter prototype
 * (`lib/features/pos/domain/cash/*.dart`, BR-CASH-001 through BR-CASH-010,
 * `docs/business_rules.md`) into a real, server-authoritative backend — the
 * Flutter classes stay the reference for field shape/state-machine
 * correctness, but every mutation now happens here, transactionally,
 * permission-gated, and remote-approved where the governing instruction
 * requires it. The Flutter `InMemory*Repository` layer (Phase 3 Sprint 3E)
 * is Wave D's own wiring target, not touched this wave.
 */

export const CASH_DRAWERS_COLLECTION = "cashDrawers";
export const CASH_SESSIONS_COLLECTION = "cashSessions";
export const CASH_MOVEMENTS_COLLECTION = "cashMovements";
export const CASH_COUNTS_COLLECTION = "cashCounts";
export const CASH_RECONCILIATIONS_COLLECTION = "cashReconciliations";
export const CASH_ADJUSTMENTS_COLLECTION = "cashAdjustments";
export const CASH_MOVEMENT_REQUESTS_COLLECTION = "cashMovementRequests";
export const CASH_ADJUSTMENT_REQUESTS_COLLECTION = "cashAdjustmentRequests";

// ---------------------------------------------------------------------
// CashDrawer — mutable registry entity (BR-CASH-001)
// ---------------------------------------------------------------------

export interface CashDrawerDoc {
  organizationId: string;
  branchId: string;
  name: string;
  isActive: boolean;
  createdAt: Timestamp;
  createdByStaffUid: string;
  updatedAt: Timestamp;
  version: number;
}

// ---------------------------------------------------------------------
// CashSession — one drawer's cash-handling session (BR-CASH-002)
// ---------------------------------------------------------------------

/**
 * `awaitingOpenApproval`/`openRejected` are AP-4 Wave B's own additions —
 * the Flutter prototype's `CashSessionStatus` had no opening-approval step
 * at all (any staff could open a drawer unconditionally). Every other value
 * is identical to `CashSessionStatus` (`lib/features/pos/domain/cash/
 * cash_session_status.dart`) — `active|pendingApproval|approved|rejected|
 * closed` keep their exact original meaning (the CLOSE-time count/
 * reconciliation cycle, BR-CASH-005/006/008), never overloaded for the
 * OPEN-time approval this wave adds.
 */
export type CashSessionStatus =
  | "awaitingOpenApproval"
  | "openRejected"
  | "active"
  | "pendingApproval"
  | "approved"
  | "rejected"
  | "closed";

const CASH_SESSION_TRANSITIONS: Readonly<Record<CashSessionStatus, readonly CashSessionStatus[]>> = {
  awaitingOpenApproval: ["active", "openRejected"],
  openRejected: [],
  active: ["pendingApproval"],
  pendingApproval: ["approved", "rejected"],
  rejected: ["pendingApproval"],
  approved: ["closed"],
  closed: [],
};

export function canTransitionCashSession(from: CashSessionStatus, to: CashSessionStatus): boolean {
  return CASH_SESSION_TRANSITIONS[from].includes(to);
}

/** BR-CASH-002 — statuses that count as "this drawer already has an open session," blocking a new open request. */
export function cashSessionCountsAsOpen(status: CashSessionStatus): boolean {
  return status !== "closed" && status !== "openRejected";
}

export interface CashSessionDoc {
  organizationId: string;
  branchId: string;
  drawerId: string;
  status: CashSessionStatus;
  /** Server-resolved via `computeBusinessDate` at open time — never client-supplied, never device local time. */
  businessDate: string; // YYYY-MM-DD
  openingFloatAmountMinorUnits: number;
  currencyCode: string;
  requestedByStaffUid: string;
  /** `null` until the session actually opens (immediately for a manager's own on-site open, or once a remote approval lands). */
  openedByStaffUid: string | null;
  openedAt: Timestamp | null;
  /**
   * BR-PAY-014-adjacent branch policy this wave introduces for cash: a
   * `cashierBound` drawer may only be operated (movements/count/close) by
   * the SAME staff uid that opened it; a `sharedDrawer` may be operated by
   * any staff with branch access — resolved once, frozen here, from
   * `branchPaymentConfig.cashRegisterModel` at open time so a later config
   * change never silently changes an in-progress session's own rule.
   */
  cashRegisterModel: "sharedDrawer" | "cashierBound";
  settledAmountMinorUnits: number; // kept current — sum of every real cashMovements doc for this session
  closedByStaffUid: string | null;
  closedAt: Timestamp | null;
  finalCashCountId: string | null;
  finalReconciliationId: string | null;
  createdAt: Timestamp;
  updatedAt: Timestamp;
  version: number;
}

// ---------------------------------------------------------------------
// CashMovement — immutable, append-only, signed by type (BR-CASH-003)
// ---------------------------------------------------------------------

export const CASH_MOVEMENT_TYPES = [
  "openingFloat",
  "cashSale",
  "cashRefund",
  "manualIn",
  "manualOut",
  "safeDeposit",
  "pettyCash",
  "expense",
  "correction",
  "closingDifference",
] as const;
export type CashMovementType = (typeof CASH_MOVEMENT_TYPES)[number];

/** `null` for `correction`/`closingDifference`, whose sign is caller/context-supplied — mirrors `CashMovementTypeDirection.isInflow` exactly. */
export function cashMovementIsInflow(type: CashMovementType): boolean | null {
  switch (type) {
    case "openingFloat":
    case "cashSale":
    case "manualIn":
      return true;
    case "cashRefund":
    case "manualOut":
    case "safeDeposit":
    case "pettyCash":
    case "expense":
      return false;
    case "correction":
    case "closingDifference":
      return null;
  }
}

/** The subset of movement types a cashier may directly REQUEST (mandatory-reason, manager-approved) — sale/refund/opening/correction/closingDifference are always system-originated, never a raw client request. */
export const REQUESTABLE_CASH_MOVEMENT_TYPES = ["manualIn", "manualOut", "safeDeposit", "pettyCash", "expense"] as const;
export type RequestableCashMovementType = (typeof REQUESTABLE_CASH_MOVEMENT_TYPES)[number];
export function sanitizeRequestableCashMovementType(raw: unknown): RequestableCashMovementType {
  if (typeof raw !== "string" || !(REQUESTABLE_CASH_MOVEMENT_TYPES as readonly string[]).includes(raw)) {
    throw new Error(`movementType must be one of: ${REQUESTABLE_CASH_MOVEMENT_TYPES.join(", ")}.`);
  }
  return raw as RequestableCashMovementType;
}

export interface CashMovementDoc {
  organizationId: string;
  branchId: string;
  sessionId: string;
  drawerId: string;
  type: CashMovementType;
  /** Signed — positive is an inflow, negative an outflow (BR-CASH-003). */
  amountMinorUnits: number;
  currencyCode: string;
  reason: string;
  actorStaffUid: string;
  timestamp: Timestamp;
  reversalOfMovementId: string | null;
  /** Set only for `cashSale`/`cashRefund` — traces back to the `paymentAttempts`/`refundRequests` doc that produced this movement (AP-4 Wave A/B integration). */
  paymentAttemptId: string | null;
  refundRequestId: string | null;
}

// ---------------------------------------------------------------------
// CashCount / CashDeclaration / CashVariance (BR-CASH-004/005/008)
// ---------------------------------------------------------------------

export type CashVarianceType = "over" | "short" | "exact";

export interface CashVarianceSnapshot {
  amountMinorUnits: number; // always >= 0, magnitude only
  type: CashVarianceType;
}

/** `actual - expected`, mirrors `CashVariance.compute` exactly. */
export function computeCashVariance(expectedMinorUnits: number, actualMinorUnits: number): CashVarianceSnapshot {
  const difference = actualMinorUnits - expectedMinorUnits;
  if (difference === 0) return { amountMinorUnits: 0, type: "exact" };
  return { amountMinorUnits: Math.abs(difference), type: difference < 0 ? "short" : "over" };
}

export interface CashCountDoc {
  organizationId: string;
  branchId: string;
  sessionId: string;
  /** Frozen at submission time — sum of every `cashMovements` doc for the session so far (BR-CASH-004). Never recomputed later. */
  expectedAmountMinorUnits: number;
  actualAmountMinorUnits: number;
  notes: string;
  variance: CashVarianceSnapshot;
  declaredByStaffUid: string;
  declaredAt: Timestamp;
}

// ---------------------------------------------------------------------
// CashReconciliation — manager review of one CashCount (BR-CASH-006/007/008)
// ---------------------------------------------------------------------

export type CashReconciliationStatus = "approved" | "rejected";

export interface CashReconciliationDoc {
  organizationId: string;
  branchId: string;
  sessionId: string;
  cashCountId: string;
  status: CashReconciliationStatus;
  reviewedByStaffUid: string;
  reviewedAt: Timestamp;
  managerComments: string;
  varianceAccepted: boolean;
  variance: CashVarianceSnapshot;
}

// ---------------------------------------------------------------------
// CashAdjustment — manager-approved correction, links to its CashMovement (BR-CASH-009)
// ---------------------------------------------------------------------

export interface CashAdjustmentDoc {
  organizationId: string;
  branchId: string;
  sessionId: string;
  movementId: string; // the `correction`-typed CashMovement this adjustment produced
  reason: string;
  requestedByStaffUid: string;
  approvedByStaffUid: string; // BR-CASH-007 — structurally never equal to requestedByStaffUid
  createdAt: Timestamp;
}

// ---------------------------------------------------------------------
// Business-day resolution — branch-timezone-authoritative, never device local time
// ---------------------------------------------------------------------

/**
 * A sale/session at 02:00 local time still belongs to YESTERDAY's business
 * day when `cutoverHour > 2` — branch-configurable
 * (`branchPaymentConfig.businessDayCutoverHour`/`timezone`, AP-4 Wave A).
 * Uses only Node's built-in `Intl` (ICU) — no new dependency. `Intl`'s
 * `hour12: false` formatting can render midnight as `"24"` rather than
 * `"00"` (a documented ICU/Node quirk) — normalized below.
 */
export function computeBusinessDate(nowUtcMs: number, timezone: string, cutoverHour: number): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    hour12: false,
  }).formatToParts(new Date(nowUtcMs));
  const get = (type: string): number => Number(parts.find((p) => p.type === type)!.value);
  const year = get("year");
  const month = get("month");
  const day = get("day");
  const hour24Raw = get("hour");
  const hour = hour24Raw === 24 ? 0 : hour24Raw;

  const pad = (n: number): string => String(n).padStart(2, "0");
  if (hour < cutoverHour) {
    const d = new Date(Date.UTC(year, month - 1, day));
    d.setUTCDate(d.getUTCDate() - 1);
    return `${d.getUTCFullYear()}-${pad(d.getUTCMonth() + 1)}-${pad(d.getUTCDate())}`;
  }
  return `${year}-${pad(month)}-${pad(day)}`;
}
