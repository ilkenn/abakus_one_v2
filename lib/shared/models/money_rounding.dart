/// The single, shared rounding policy for every fractional monetary
/// computation in this app — VAT extraction, percentage discounts, foreign-
/// currency conversion. One implementation so "which rounding rule" is
/// never answered two different ways in two different files.
///
/// Approved policy: **Round Half Away From Zero** — a tie (exactly `.5` of
/// a minor unit) rounds away from zero (`0.5 -> 1`, `-0.5 -> -1`), not to
/// even ("banker's rounding") and not always up. This app's amounts are
/// never expected to be negative in practice, but the rule is defined for
/// both signs so it stays correct if a computation ever produces one
/// (e.g. an intermediate discount calculation) rather than silently doing
/// the wrong thing.
abstract final class MoneyRounding {
  MoneyRounding._();

  /// Rounds the exact rational value `numerator / denominator` to the
  /// nearest integer, ties rounding away from zero. [denominator] must be
  /// positive; [numerator] may be any sign.
  static int halfAwayFromZero(int numerator, int denominator) {
    assert(denominator > 0, 'denominator must be positive');
    if (numerator == 0) return 0;
    final sign = numerator.isNegative ? -1 : 1;
    final absNumerator = numerator.abs();
    final quotient = absNumerator ~/ denominator;
    final remainder = absNumerator % denominator;
    // remainder / denominator >= 1/2  <=>  2 * remainder >= denominator
    final roundedUp = (2 * remainder) >= denominator;
    return sign * (roundedUp ? quotient + 1 : quotient);
  }
}
