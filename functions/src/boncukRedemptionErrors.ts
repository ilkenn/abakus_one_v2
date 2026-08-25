import { HttpsError } from "firebase-functions/v2/https";

/**
 * `boncukRedemptionErrors` — Boncuk Loyalty Program P5-B (2026-08-24).
 *
 * Extracted from `submitTakeawayOrder.ts` (P4-E-B, 2026-08-22) into its own
 * neutral, channel-agnostic module so `submitDeliveryOrder.ts` can reuse the
 * SAME stable-error-reason vocabulary and sanitizer rather than a second,
 * private copy. **Byte-for-byte behavior preserved for takeaway** —
 * `submitTakeawayOrder.ts` now imports every export below instead of
 * defining them locally; nothing about the reason strings, the `details`
 * shape, or the sanitizer's own validation logic changed.
 *
 * Stable, machine-readable failure reasons for a Boncuk-redemption-specific
 * rejection, carried in `HttpsError`'s own `details` field
 * (`{ reason: BoncukRedemptionErrorReason }`) — round-trips to the Dart
 * `cloud_functions` client verbatim as `FirebaseFunctionsException.details`.
 * Necessary because `code` alone is insufficient: `invalid-argument`/
 * `failed-precondition` are ALSO thrown by entirely unrelated validation in
 * both `submitTakeawayOrder.ts` and `submitDeliveryOrder.ts` (contact
 * fields, pickup time, branch/address scope, item shape, ...), so a client
 * branching on `code` alone cannot safely tell "your Boncuk selection is
 * now invalid" apart from any of those. `reason` is the one stable value a
 * client may branch business logic on; `message` remains human-readable/
 * diagnostic only, never parsed by a caller.
 */
export const BONCUK_REDEMPTION_ERROR_REASONS = [
  "boncuk/exceeds-max-usable",
  "boncuk/account-unavailable",
  "boncuk/policy-unavailable",
  "boncuk/redemption-not-allowed",
  // Boncuk Loyalty P7-C (2026-08-24) — catalog-reward-specific reasons,
  // added to the SAME stable `details.reason` vocabulary rather than a
  // second, parallel error channel, so the Flutter client's existing
  // `boncukErrorReason`-keyed branch (`reservation_error_messages.dart`/
  // `takeaway_checkout_screen.dart`'s own equivalents) already recognizes
  // "this is a loyalty-related rejection" for free — only the specific
  // `case` values are new.
  "catalogReward/reward-not-found",
  "catalogReward/reward-not-currently-valid",
  "catalogReward/product-not-in-cart",
  "catalogReward/insufficient-balance",
  "catalogReward/account-unavailable",
  "catalogReward/benefit-stacking-not-allowed",
  // Boncuk Loyalty P7-C.1 (2026-08-24) — the reward is real/valid/product-
  // eligible, but its own `eligibleChannels` does not include the real,
  // server-derived channel of THIS order (never the client's own claim).
  "catalogReward/channel-not-eligible",
  // Server-Authoritative Campaign Engine P8-B (2026-08-25) — the new,
  // channel-neutral stacking reason `enforceBenefitExclusivity`
  // (`benefitExclusivity.ts`) uses when a request names more than one of
  // {Boncuk redemption, catalog reward, campaign}. Deliberately NOT reusing
  // `"catalogReward/benefit-stacking-not-allowed"` — that reason is
  // channel-specific text already asserted on by existing tests for the
  // two-benefit case; this is the neutral reason for the now-three-benefit
  // check, added to the SAME shared vocabulary rather than a parallel one.
  "benefit/stacking-not-allowed",
] as const;
export type BoncukRedemptionErrorReason = (typeof BONCUK_REDEMPTION_ERROR_REASONS)[number];

export function boncukError(
  code: "invalid-argument" | "failed-precondition" | "internal",
  message: string,
  reason: BoncukRedemptionErrorReason,
): never {
  throw new HttpsError(code, message, { reason });
}

/**
 * Boncuk Loyalty P7-C (2026-08-24) — the ONE shared `selectedBenefitType`
 * union, replacing the previously independently hand-typed `"none" |
 * "boncukRedemption"` literal that appeared at each order-submission call
 * site. Exported from this already-shared, already-imported-by-every-
 * channel module rather than a new file. Channels that don't yet support
 * `"catalogReward"` (delivery, reservation preorder) are deliberately left
 * on their own existing local unions this phase — widening THEIR type to
 * include a value they can never actually set would be misleading, not a
 * genuine duplication removal.
 *
 * **`"campaign"` added — Server-Authoritative Campaign Engine P8-B
 * (2026-08-25).** Foundation only: no `submit*Order.ts` file sets this
 * value yet (checkout campaign redemption is explicitly out of scope this
 * phase) — the member exists so `campaignEngine.ts`'s types and
 * `benefitExclusivity.ts`'s new shared helper have a real value to
 * reference now, rather than a placeholder added later alongside the
 * checkout wiring itself. `"coupon"` remains reserved and unimplemented,
 * unchanged.
 */
export type SelectedBenefitType = "none" | "boncukRedemption" | "catalogReward" | "campaign";

/**
 * `undefined`/`null` both mean "no reward selected" — collapses to `null`.
 * Real existence/eligibility/validity is never decided here; this only
 * validates SHAPE, mirroring `sanitizeRequestedBoncukAmount`'s own
 * minimal-shape-check-only philosophy (the real semantic validation
 * happens transactionally against `loyaltyRewardCatalog`).
 */
export function sanitizeSelectedRewardId(raw: unknown): string | null {
  if (raw === undefined || raw === null) return null;
  if (typeof raw !== "string" || raw.trim().length === 0) {
    throw new HttpsError("invalid-argument", "selectedRewardId must be a non-empty string.");
  }
  return raw;
}

/**
 * Boncuk Loyalty P4-B — the customer submits only a whole Boncuk COUNT,
 * never a value/rate/cap/remaining-payable amount (those are always
 * server-resolved from the active policy — P4-B locked rule). Absent/`null`
 * means "no Boncuk requested," identical to an explicit `0`. Channel-
 * agnostic — reused verbatim by both `submitTakeawayOrder.ts` and
 * `submitDeliveryOrder.ts`.
 */
export function sanitizeRequestedBoncukAmount(raw: unknown): number {
  if (raw === undefined || raw === null) return 0;
  if (typeof raw !== "number" || !Number.isInteger(raw) || raw < 0) {
    throw new HttpsError("invalid-argument", "requestedBoncukAmount must be a non-negative integer.");
  }
  return raw as number;
}
