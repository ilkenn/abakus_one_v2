import type { Timestamp } from "firebase-admin/firestore";

/**
 * AP-3 Wave 2 — money-safe Check/allocation domain contracts (corrected AP-3
 * Stage A report §2, further refined by the AP-3 Stage B mandatory
 * refinements). No Firestore I/O lives here — mirrors `tableSessionConfig.ts`'s
 * own "policy/vocabulary only" shape.
 *
 * **Flat top-level convention preserved** — `checks`, `checkAllocations`,
 * `checkFinancialAdjustments` are three top-level collections, never a
 * `checks/{id}/allocations` subcollection, matching this codebase's
 * established convention (every other AP-1/AP-2/AP-3 aggregate —
 * `tableSessions`, `guestSubAccounts`, `orders`, `remoteApprovalRequests` —
 * is flat top-level; no ADR proposes or approves a subcollection exception).
 *
 * **Unified allocation model — the source-traceability fix.** The corrected
 * Stage A report's own draft discriminated allocations into `kind: "line"`
 * (quantity-based) vs. `kind: "freeAmount"` (an unreferenced bare amount) —
 * the Stage B mandatory refinement #3 rejected the `freeAmount` half of that
 * as fiscally unsafe: "an unreferenced freeAmount allocation is insufficient
 * for later fiscal/refund reconciliation." The fix used here: EVERY
 * allocation, regardless of how staff triggered it (product/quantity/
 * customer/headcount/freeAmount), carries an explicit `sourceComposition`
 * array — which accepted order line(s), and exactly how much money was
 * drawn from each. A `freeAmount`/`headcount` split still draws from real
 * source lines, it simply isn't constrained to whole units.
 *
 * **The concurrency lock — `orderLineAllocationLedgers`.** Per mandatory
 * refinement #3 ("do not rely only on a query returning no allocation as
 * the concurrency lock"), conservation is enforced via a real, transaction-
 * participating document per source line — `remainingQuantity`/
 * `remainingValueMinorUnits`, decremented inside the SAME transaction that
 * creates an allocation. Two concurrent attempts to allocate the same
 * line's last remaining value can never both succeed: Firestore retries the
 * loser's transaction against the winner's already-committed decrement,
 * exactly mirroring Wave 1's `restaurantTables.activeTableSessionId` lock
 * pattern (`docs/decisions.md` ADR-036) and `openReservationTable`'s own
 * precedent before that.
 */

export const CHECKS_COLLECTION = "checks";
export const CHECK_ALLOCATIONS_COLLECTION = "checkAllocations";
export const CHECK_FINANCIAL_ADJUSTMENTS_COLLECTION = "checkFinancialAdjustments";
export const ORDER_LINE_ALLOCATION_LEDGERS_COLLECTION = "orderLineAllocationLedgers";

/**
 * `"paid"` is AP-4 Wave A's own addition (`docs/payment_cash_fiscal
 * _architecture.md` §6 handoff contract: "AP-3 never writes status:'paid' —
 * that and everything after readyForPayment belongs to AP-4"). Written
 * exactly once, transactionally, by `paymentEngine.ts`'s `recordPaymentAttempt`
 * the moment a `PaymentSession` reaches `completed` — never by any AP-3
 * check-mutation callable, all of which remain scoped to
 * `open`/`readyForPayment`/`cancelled` exactly as before.
 */
export type CheckStatus = "open" | "readyForPayment" | "paid" | "cancelled";

export interface CheckDoc {
  organizationId: string;
  branchId: string;
  tableSessionId: string;
  status: CheckStatus;
  /** AP-3 sets `false`; AP-4's own first `PaymentAttempt` is the only thing that ever flips this `true`. Once `true`, every further allocation mutation requires remote approval (corrected report §2.3). */
  paymentActivityStarted: boolean;
  /** Authoritative only because it is recomputed, transactionally, from this check's own active allocations on every mutation — never trusted as an independently-editable field. */
  computedTotalMinorUnits: number;
  currencyCode: string;
  openedAt: Timestamp;
  readyForPaymentAt: Timestamp | null;
  cancelledAt: Timestamp | null;
  createdByStaffUid: string;
  version: number;
}

export type SplitMethod = "product" | "quantity" | "customer" | "headcount" | "freeAmount";

export interface SourceCompositionEntry {
  sourceOrderId: string;
  sourceLineIndex: number;
  /** Whole units claimed from this line by this allocation; `null` for a money-only (freeAmount/headcount) draw that doesn't claim a whole unit. */
  quantity: number | null;
  amountMinorUnits: number;
}

export type CheckAllocationStatus = "active" | "reversed" | "transferred";

export interface CheckAllocationDoc {
  checkId: string;
  organizationId: string;
  branchId: string;
  tableSessionId: string;
  subAccountId: string;
  splitMethod: SplitMethod;
  sourceComposition: SourceCompositionEntry[];
  /** Always exactly `sum(sourceComposition[].amountMinorUnits)` — asserted, never independently set. */
  allocatedAmountMinorUnits: number;
  currencyCode: string;
  status: CheckAllocationStatus;
  note: string | null;
  createdAt: Timestamp;
  createdByStaffUid: string;
  version: number;
}

export interface OrderLineAllocationLedgerDoc {
  organizationId: string;
  branchId: string;
  tableSessionId: string;
  sourceOrderId: string;
  sourceLineIndex: number;
  /** Snapshotted once, at first allocation against this line — the line's own accepted quantity/value at that moment. Lines are immutable once accepted, so this never drifts. */
  originalQuantity: number;
  lineValueMinorUnits: number;
  currencyCode: string;
  remainingQuantity: number;
  remainingValueMinorUnits: number;
  version: number;
}

export function orderLineAllocationLedgerId(sourceOrderId: string, sourceLineIndex: number): string {
  return `${sourceOrderId}_${sourceLineIndex}`;
}

/** A line is allocatable once accepted — a `pendingApproval`/`rejected`/`proposedChange` line has no settled value to allocate yet. */
export function isLineAllocatable(line: { status?: string }): boolean {
  return line.status === "accepted";
}

export function computeLineValueMinorUnits(line: {
  quantity: number;
  unitPrice?: { minorUnits: number };
  lineDiscount?: { minorUnits: number };
  modifiers?: Array<{ unitExtraPrice?: { minorUnits: number }; quantity: number }>;
}): number {
  const unitPrice = line.unitPrice?.minorUnits ?? 0;
  const modifierTotal = (line.modifiers ?? []).reduce(
    (sum, m) => sum + (m.unitExtraPrice?.minorUnits ?? 0) * m.quantity,
    0,
  );
  const discount = line.lineDiscount?.minorUnits ?? 0;
  return (unitPrice + modifierTotal) * line.quantity - discount;
}
