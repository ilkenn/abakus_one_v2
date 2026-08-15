/**
 * Minimal integer-minor-units money arithmetic — Faz D.3 (Server-
 * Authoritative Pricing + Takeaway Order Creation). Hand-mirrors
 * `lib/shared/models/money.dart`'s `Money`/`MoneyRounding` exactly (same
 * reasoning as `orderStatus.ts` mirroring `order_status.dart` — no
 * Dart<->TypeScript code-sharing mechanism in this repository). Every
 * amount here is an integer count of TRY kuruş (minor units) — never a
 * floating-point number — matching this codebase's own "money math never
 * as raw uncontrolled double" rule (CLAUDE.md §4) applied server-side for
 * the first time.
 */

/** Mirrors `MoneyRounding.halfAwayFromZero` exactly: rounds the exact rational `numerator / denominator` to the nearest integer, ties away from zero. `denominator` must be positive. */
export function roundHalfAwayFromZero(numerator: number, denominator: number): number {
  if (denominator <= 0) {
    throw new Error("denominator must be positive");
  }
  if (numerator === 0) return 0;
  const sign = numerator < 0 ? -1 : 1;
  const absNumerator = Math.abs(numerator);
  const quotient = Math.floor(absNumerator / denominator);
  const remainder = absNumerator % denominator;
  const roundedUp = 2 * remainder >= denominator;
  return sign * (roundedUp ? quotient + 1 : quotient);
}

/**
 * VAT extraction from a gross (VAT-inclusive) amount — mirrors
 * `TaxRate.vatAmountOf`'s exact formula:
 * `grossMinorUnits * basisPoints / (10000 + basisPoints)`, rounded half
 * away from zero.
 */
export function vatAmountOf(grossMinorUnits: number, basisPoints: number): number {
  return roundHalfAwayFromZero(grossMinorUnits * basisPoints, 10000 + basisPoints);
}

export function taxableBaseOf(grossMinorUnits: number, basisPoints: number): number {
  return grossMinorUnits - vatAmountOf(grossMinorUnits, basisPoints);
}
