import { sha256Hex } from "./submitTakeawayOrder";
import { HttpsError } from "firebase-functions/v2/https";

/**
 * `loyaltyLedger` — Boncuk Loyalty Program P1/P2A/P2B (2026-08-20 → 2026-08-22).
 *
 * Shared server-side domain contracts for the loyalty ledger — NO Firestore
 * I/O in this file. See `docs/business_rules.md`'s `BR-LOYALTY-001`-`016`
 * for the locked business rules this schema serves, and
 * `docs/firestore_data_model.md`/`docs/decisions.md`'s P2B-A/P2B-A.1/P2B-B
 * entries for the full accounting-semantics design and correction history.
 *
 * **P2B-B contract correction (2026-08-22)** — the original P1 `deltaBoncuk`
 * field is REMOVED, not deprecated-and-kept. A single signed delta cannot
 * unambiguously represent an event that changes gross entitlement,
 * spendable balance, and debt by three different amounts at once (a
 * reversal, or an earn that partially pays down debt) — see
 * `BR-LOYALTY-016`. Every entry now carries three first-class, always-
 * populated (never null) signed accounting effects instead:
 * `entitlementDeltaBoncuk`/`spendableDeltaBoncuk`/`debtDeltaBoncuk`.
 */

export const LOYALTY_ACCOUNTS_COLLECTION = "loyaltyAccounts";
export const LOYALTY_LEDGER_ENTRIES_COLLECTION = "loyaltyLedgerEntries";

// BR-LOYALTY-001/005 — integer minor units (kuruş) only, never a
// floating-point representation, mirroring this codebase's established
// `Money`/minor-units discipline (`functions/src/takeawayMoney.ts`).
export const BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK = 5000; // 50 TL = 1 Boncuk
export const BONCUK_REDEMPTION_VALUE_MINOR_UNITS_PER_BONCUK = 200; // 1 Boncuk = 2 TL

// Closed entry-type enum — mirrors `customerPhotoUploadGrants.ts`'s
// `PHOTO_UPLOAD_PURPOSES` pattern exactly (`as const` array -> derived
// union via `(typeof X)[number]` -> a `sanitizeX` validator), the
// established convention in this codebase for a closed Firestore-stored
// string value. P1 defines the full closed set; P2+ phases implement the
// write behavior for each, one at a time — adding a new entry type later
// would still be a deliberate, reviewed change to this one array, never
// an open/free-form string.
export const LEDGER_ENTRY_TYPES = [
  "orderEarn",
  "orderEarnReversal",
  "boncukRedemption",
  "boncukRedemptionRestore",
  "catalogRedemption",
  "catalogRedemptionRestore",
  "wheelEarn",
  "wheelExpiry",
  "taskEarn",
  "taskReversal",
  "adminAdjustment",
] as const;
export type LedgerEntryType = (typeof LEDGER_ENTRY_TYPES)[number];

export function sanitizeEntryType(raw: unknown): LedgerEntryType {
  if (typeof raw !== "string" || !(LEDGER_ENTRY_TYPES as readonly string[]).includes(raw)) {
    throw new HttpsError(
      "invalid-argument",
      `entryType must be one of: ${LEDGER_ENTRY_TYPES.join(", ")}.`,
    );
  }
  return raw as LedgerEntryType;
}

/**
 * Closed, per-`entryType`-documented metadata — reserved for genuinely
 * entry-type-unique, NON-ACCOUNTING details only (P2B-B: financially
 * meaningful state transitions belong in the first-class fields on
 * `LoyaltyLedgerEntry` itself, never here — see the interface's own doc
 * comment). An entry type not listed here explicitly carries no extra
 * metadata at all.
 */
export type LoyaltyLedgerMetadata =
  | { entryType: "catalogRedemption" | "catalogRedemptionRestore"; rewardId: string }
  | { entryType: "taskEarn" | "taskReversal"; taskType: string }
  | { entryType: "adminAdjustment"; staffActorId: string; reason: string };

/**
 * The immutable, append-only ledger entry contract.
 *
 * **Three first-class accounting effects (P2B-B, `BR-LOYALTY-016`)** —
 * always populated, never `null`, for every entry type:
 * - `entitlementDeltaBoncuk` — change in the customer's gross valid Boncuk
 *   claim this event caused, before any debt/redemption accounting.
 *   Nonzero only for earning/reversal-direction entries (`orderEarn`,
 *   `orderEarnReversal`, and — once designed — `wheelEarn`/`wheelExpiry`/
 *   `taskEarn`/`taskReversal`). **Always `0` for every redemption/
 *   restoration-direction entry** (`boncukRedemption`/
 *   `boncukRedemptionRestore`/`catalogRedemption`/`catalogRedemptionRestore`)
 *   — spending or restoring already-earned Boncuk never changes how much
 *   was earned, only how much remains spendable.
 * - `spendableDeltaBoncuk` — the actual change to `spendableBalance`.
 *   Summing this field across a customer's entire ledger reconstructs
 *   `spendableBalance` exactly, for any entry type.
 * - `debtDeltaBoncuk` — the actual change to `boncukDebt`. Positive when
 *   debt grows (a clawback exceeds available spendable), negative when
 *   debt shrinks (later earning pays it down). Always `0` for redemption/
 *   restoration-direction entries.
 *
 * **Invariant for earning/reversal-direction entries only**:
 * `entitlementDeltaBoncuk === spendableDeltaBoncuk - debtDeltaBoncuk`. Does
 * NOT hold for redemption/restoration entries by design.
 */
export interface LoyaltyLedgerEntry {
  organizationId: string;
  customerId: string;
  entryType: LedgerEntryType;

  entitlementDeltaBoncuk: number;
  spendableDeltaBoncuk: number;
  debtDeltaBoncuk: number;

  /** Generic, `entryType`-dependent pointer (orderId/wheelSpinId/taskSubmissionId/staffActionId/refund-or-cancellation id). */
  sourceId: string;
  /**
   * Denormalized separately from `sourceId` specifically because
   * "every ledger entry for order X" is the single most common future
   * query (refund reconciliation, support tooling, audit) — `null` for
   * entry types never linked to an order (`wheelEarn`, `wheelExpiry`,
   * `taskEarn`, `taskReversal`, `adminAdjustment`).
   */
  orderId: string | null;

  // ---------------------------------------------------------------------
  // Order-earning-family provenance (`orderEarn`/`orderEarnReversal` only)
  // — null for every other entry type. Deliberately redundant with each
  // other (before/after aggregate implies before/after entitlement implies
  // before/after remainder) so a reader never has to recompute financially
  // meaningful state to audit an entry — a standard, accepted trade-off in
  // append-only financial ledgers (storage cost for zero-recomputation
  // trust), per P2B-A.1.
  // ---------------------------------------------------------------------

  /** The net eligible spend this specific event contributed/removed (this order's own amount, or the refunded amount for a reversal). */
  amountBasisMinorUnits: number | null;
  /** `loyaltyAccounts.orderEligibleNetSpendMinorUnits` immediately before this event. */
  orderEligibleNetSpendBeforeMinorUnits: number | null;
  /** `loyaltyAccounts.orderEligibleNetSpendMinorUnits` immediately after this event. */
  orderEligibleNetSpendAfterMinorUnits: number | null;
  /** `floor(orderEligibleNetSpendBeforeMinorUnits / 5000)`. */
  orderEntitlementBeforeBoncuk: number | null;
  /** `floor(orderEligibleNetSpendAfterMinorUnits / 5000)`. */
  orderEntitlementAfterBoncuk: number | null;
  /** `orderEligibleNetSpendBeforeMinorUnits % 5000`. */
  remainderBeforeMinorUnits: number | null;
  /** `orderEligibleNetSpendAfterMinorUnits % 5000`. */
  remainderAfterMinorUnits: number | null;
  /** Rate-at-time-of-entry snapshot — so a historical entry stays self-describing if the 50 TL rate ever changes. */
  earningRateMinorUnitsPerBoncuk: number | null;

  // ---------------------------------------------------------------------
  // Debt provenance — populated whenever debt participates in this event
  // (any earning entry type when debt existed at the time; a reversal that
  // creates/increases debt). `null` only when debt has never existed for
  // this account at the time of this event.
  // ---------------------------------------------------------------------

  debtBeforeBoncuk: number | null;
  debtAfterBoncuk: number | null;

  /** Rate-at-time-of-entry snapshot — redemption-family only. */
  redemptionRateMinorUnitsPerBoncuk: number | null;

  /** Queryable/audit-readable idempotency value — distinct from the deterministic document id itself. */
  idempotencyKey: string;
  /** The reversed/restored entry's id, for `*Reversal`/`*Restore` types. */
  reversalOf: string | null;
  /** `wheelEarn` only — unused until wheel-expiry mechanics are decided (`docs/business_rules.md` `BR-LOYALTY-009`). */
  expiresAt: FirebaseFirestore.Timestamp | null;
  metadata: LoyaltyLedgerMetadata | null;
  // `createdAt` is stamped by the writer at write time (`Timestamp.now()`)
  // — deliberately not part of this input contract.
}

/**
 * Correction B (P1 locked instruction) — a deterministic, tenant +
 * entryType + source-scoped ledger entry id, never a naked `{orderId}-earn`
 * style string. Reuses the real, already-exported `sha256Hex`
 * (`submitTakeawayOrder.ts`) rather than duplicating it a third time
 * (`submitReservation.ts`'s own private re-implementation is exactly the
 * inconsistency this avoids). `customerId` (a Firebase Auth uid) is an
 * opaque identifier, never raw PII such as phone/email — none of those
 * are ever accepted as input here.
 *
 * - Reproducible: identical inputs always produce the identical id.
 * - Bounded: a short literal prefix + a fixed-length 64-char hex digest,
 *   far under Firestore's document-id length limit.
 * - Firestore-safe: hex digits and hyphens only — never `/`, never `.`/`..`,
 *   never leading/trailing whitespace.
 * - Tenant-scoped / entry-type-scoped / source-scoped: all three are
 *   direct hash inputs, so a collision requires an exact match on every
 *   one of organizationId, customerId, entryType, and sourceId at once.
 *
 * Reused unchanged for `orderEarnReversal` (P2B) — a full reversal's
 * `sourceId` is the refunded order's own id, giving a deterministic id
 * distinct from that same order's `orderEarn` entry purely because
 * `entryType` differs.
 */
export function deriveLoyaltyLedgerEntryId(params: {
  organizationId: string;
  customerId: string;
  entryType: LedgerEntryType;
  sourceId: string;
}): string {
  const { organizationId, customerId, entryType, sourceId } = params;
  return `loyalty-${sha256Hex(`${organizationId}|${customerId}|${entryType}|${sourceId}`)}`;
}
