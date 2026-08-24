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
