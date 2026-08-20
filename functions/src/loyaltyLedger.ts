import { sha256Hex } from "./submitTakeawayOrder";
import { HttpsError } from "firebase-functions/v2/https";

/**
 * `loyaltyLedger` — Boncuk Loyalty Program P1 (2026-08-20).
 *
 * Shared server-side domain contracts for the loyalty ledger foundation —
 * NO Firestore I/O in this file. `getCustomerLoyaltySnapshot.ts` is the
 * only P1 writer, and it only ever touches `loyaltyAccounts`; nothing in
 * this phase writes a `loyaltyLedgerEntries` document — these types/
 * helpers exist so P2+ (order earning/reversal, redemption, catalog,
 * wheel, tasks) never needs to redesign the ledger shape, per
 * `docs/decisions.md`'s P0-A/P1 entries.
 *
 * See `docs/business_rules.md`'s `BR-LOYALTY-001`-`011` for the locked
 * business rules this schema serves, and `docs/firestore_data_model.md`
 * for the full field-by-field collection documentation.
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
 * Closed, per-`entryType`-documented metadata — deliberately never a
 * generic `Map<string, unknown>` free-for-all. An entry type not listed
 * here explicitly (`orderEarn`, `orderEarnReversal`, `boncukRedemption`,
 * `boncukRedemptionRestore`, `wheelEarn`, `wheelExpiry`) carries no extra
 * metadata at all — every field a future reader needs for those types
 * already exists as a top-level `LoyaltyLedgerEntry` field
 * (`orderId`/`amountBasisMinorUnits`/etc.).
 */
export type LoyaltyLedgerMetadata =
  | { entryType: "catalogRedemption" | "catalogRedemptionRestore"; rewardId: string }
  | { entryType: "taskEarn" | "taskReversal"; taskType: string }
  | { entryType: "adminAdjustment"; staffActorId: string; reason: string };

/**
 * The immutable, append-only ledger entry contract. Not written by any
 * function this phase — establishes the shape P2+ writers must produce.
 */
export interface LoyaltyLedgerEntry {
  organizationId: string;
  customerId: string;
  entryType: LedgerEntryType;
  /** Signed — positive for earn/restore, negative for redemption/reversal/expiry. */
  deltaBoncuk: number;
  /** Generic, `entryType`-dependent pointer (orderId/wheelSpinId/taskSubmissionId/staffActionId). */
  sourceId: string;
  /**
   * Denormalized separately from `sourceId` specifically because
   * "every ledger entry for order X" is the single most common future
   * query (refund reconciliation, support tooling, audit) — `null` for
   * entry types never linked to an order (`wheelEarn`, `wheelExpiry`,
   * `taskEarn`, `taskReversal`, `adminAdjustment`).
   */
  orderId: string | null;
  /** The net eligible spend (minor units) this entry's earning was calculated from — `orderEarn` only. */
  amountBasisMinorUnits: number | null;
  /** Only meaningful for `orderEarn`/`orderEarnReversal` — makes the earning remainder independently reconstructable from the ledger alone. */
  remainderBeforeMinorUnits: number | null;
  remainderAfterMinorUnits: number | null;
  /**
   * Rate-at-time-of-entry snapshots — so a historical entry stays
   * self-describing if `BONCUK_EARNING_RATE_MINOR_UNITS_PER_BONCUK`/
   * `BONCUK_REDEMPTION_VALUE_MINOR_UNITS_PER_BONCUK` ever change later.
   */
  earningRateMinorUnitsPerBoncuk: number | null;
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
