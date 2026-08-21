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
 *
 * **Configurable Loyalty Economics correction (2026-08-24)** — the fixed
 * `BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK`/
 * `BONCUK_REDEMPTION_VALUE_MINOR_UNITS_PER_BONCUK` constants that used to
 * live here are REMOVED entirely, not deprecated-and-kept. Boncuk economics
 * are no longer a compile-time constant for any organization — every
 * earning/reversal computation now resolves the organization's real,
 * server-authoritative `loyaltyPolicies/{organizationId}` document via
 * `functions/src/loyaltyPolicy.ts`. The locked initial economics (50 TL = 5
 * Boncuk, 1 Boncuk = 1 TL, 50% max redemption) now live in
 * `loyaltyPolicy.ts`'s `DEFAULT_LOYALTY_POLICY_ECONOMICS`, auto-provisioned
 * per organization on a genuine first use, not hardcoded here.
 *
 * **Same-day correction (2026-08-24) — exact-ratio economics, no derived
 * unit rate.** A single reduced "minor units per 1 Boncuk" rate
 * (`earningSpendMinorUnits / earningBoncukAmount`) cannot represent every
 * Admin-configurable ratio — `5000 minor units → 3 Boncuk` has no
 * whole-number unit rate at all. `earningRateMinorUnitsPerBoncuk` is
 * REMOVED from `LoyaltyLedgerEntry`; every `orderEarn`/`orderEarnReversal`
 * entry now snapshots the raw ratio directly
 * (`earningSpendMinorUnits`/`earningBoncukAmount`), and every entitlement
 * computation uses exact `BigInt` integer arithmetic — never floating
 * point, never rounding drift, for any ratio.
 *
 * **Fractional Entitlement Carry correction (this pass)** — the currency-
 * denominated, per-policy-EPOCH remainder fields
 * (`orderEligibleNetSpendBeforeMinorUnits`/`orderEligibleNetSpendAfterMinorUnits`/
 * `orderEntitlementBeforeBoncuk`/`orderEntitlementAfterBoncuk`/
 * `remainderBeforeMinorUnits`/`remainderAfterMinorUnits`/`earningEpochReset`)
 * are REMOVED. That design was reviewed and rejected: resetting the
 * customer's in-progress remainder to `0` whenever the organization's
 * policy version changed FORFEITED real, economically-earned partial
 * progress — unacceptable even though the reset itself never re-rated old
 * spend. They are replaced by four fields expressing the customer's
 * partial progress as an EXACT, POLICY-INDEPENDENT FRACTION of one whole
 * Boncuk — `earningCarryNumeratorBefore`/`earningCarryDenominatorBefore`/
 * `earningCarryNumeratorAfter`/`earningCarryDenominatorAfter` (canonical
 * non-negative-integer DECIMAL STRINGS, never `Number` — see
 * `loyaltyPolicy.ts`'s `parseCarryComponent`/`formatCarryComponent` for
 * why). A policy change can only ever affect the RATE at which BRAND-NEW
 * spend converts into fractional Boncuk from this point forward — the
 * carry itself is never reinterpreted, migrated onto a new ratio, or
 * reset; it simply keeps accumulating, combined exactly with whatever
 * ratio is active at the moment each new order's spend is rated. See
 * `loyaltyOrderEarning.ts`'s own doc comment for the full model and
 * `loyaltyPolicy.ts`'s `combineCarryWithEarning` for the actual math.
 */

export const LOYALTY_ACCOUNTS_COLLECTION = "loyaltyAccounts";
export const LOYALTY_LEDGER_ENTRIES_COLLECTION = "loyaltyLedgerEntries";

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
  /**
   * The customer's exact, policy-independent Boncuk-fraction carry
   * immediately BEFORE this event — canonical non-negative-integer decimal
   * strings (`loyaltyPolicy.ts`'s `formatCarryComponent`/
   * `parseCarryComponent` — never `Number`, since a carry denominator can
   * exceed `Number.MAX_SAFE_INTEGER` after a handful of policy changes).
   * **Never reinterpreted by a later policy change** — this is precisely
   * the value a future reversal replay reads verbatim to restore the
   * account to its pre-this-event state (`loyaltyReversalMath.ts`).
   */
  earningCarryNumeratorBefore: string | null;
  earningCarryDenominatorBefore: string | null;
  /** The carry immediately AFTER this event — same shape/discipline as the "Before" pair. */
  earningCarryNumeratorAfter: string | null;
  earningCarryDenominatorAfter: string | null;
  /**
   * The RAW ratio that applied when this entry was written — the
   * organization's `loyaltyPolicies.earningSpendMinorUnits`/
   * `earningBoncukAmount` at write time, never the current policy. A
   * historical entry therefore stays self-describing and exactly
   * reconstructable (including for a future reversal, which MUST use these
   * original values, never today's policy) no matter how the
   * organization's policy changes afterward.
   */
  earningSpendMinorUnits: number | null;
  earningBoncukAmount: number | null;
  /** The `loyaltyPolicies/{organizationId}.version` that was active when this entry was written — the direct link from a ledger entry back to its exact policy-history record in `loyaltyPolicyVersions`. Audit provenance only — does NOT drive any reset/re-rating behavior (there is none); `null` only for an entry written before this field existed. */
  loyaltyPolicyVersion: number | null;

  // ---------------------------------------------------------------------
  // Debt provenance — populated whenever debt participates in this event
  // (any earning entry type when debt existed at the time; a reversal that
  // creates/increases debt). `null` only when debt has never existed for
  // this account at the time of this event.
  // ---------------------------------------------------------------------

  debtBeforeBoncuk: number | null;
  debtAfterBoncuk: number | null;

  /**
   * Value-at-time-of-entry snapshot — redemption-family only (no writer
   * exists yet). Unlike the earning side, this is never a ratio requiring
   * reduction — `redemptionValueMinorUnitsPerBoncuk` is always the direct
   * minor-units value of 1 Boncuk, so no exact-ratio math is needed here.
   * Renamed from the original `redemptionRateMinorUnitsPerBoncuk`
   * (2026-08-24) purely for naming consistency with `loyaltyPolicy.ts`'s
   * own field name — no behavior change, since no writer exists yet.
   */
  redemptionValueMinorUnitsPerBoncuk: number | null;
  /** Value-at-time-of-entry snapshot — redemption-family only (no writer exists yet). New field (2026-08-24), reserved so a future redemption entry is self-contained without reading today's policy for its own cap. */
  maxRedemptionBasisPoints: number | null;

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
