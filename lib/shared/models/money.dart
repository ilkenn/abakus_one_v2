import '../../core/errors/business_rule_violation.dart';
import 'currency.dart';
import 'money_rounding.dart';

/// An exact monetary amount: an integer count of a [currency]'s minor
/// units (kuruş/cents), never a `double`. Every arithmetic operation that
/// would otherwise lose precision (a percentage, a currency conversion)
/// goes through [MoneyRounding.halfAwayFromZero] instead of floating-point
/// math.
///
/// Two [Money] values only ever combine (`+`, `-`, comparisons) when they
/// share a [currency] — a mismatch throws [CurrencyMismatchViolation]
/// rather than silently coercing one side, per this app's "no silent
/// fallback for invalid business data" rule.
class Money implements Comparable<Money> {
  const Money(this.minorUnits, this.currency);

  /// Convenience constructor for a whole-unit amount (e.g.
  /// `Money.fromWhole(5, Currency.tryLira)` for 5.00 TRY) — avoids writing
  /// out `500` by hand at call sites like policy constants, without ever
  /// touching `double`.
  factory Money.fromWhole(int wholeUnits, Currency currency) {
    return Money(wholeUnits * currency.minorUnitsPerWhole, currency);
  }

  factory Money.zero(Currency currency) => Money(0, currency);

  /// Bridges an existing `double`-typed TRY amount (`CartItem.price`,
  /// `MenuProduct.basePrice`, `ModifierOption.extraPrice`, ...) into
  /// [Money]. **Only** for use at that exact boundary (the cart-to-order
  /// mapper) — no domain type constructed after that boundary should ever
  /// go back through a `double` again. Rounds to the nearest kuruş, ties
  /// away from zero, matching this app's one rounding policy everywhere
  /// else.
  factory Money.fromLegacyDoubleTry(double amountInTry) {
    final minorUnits =
        (amountInTry * Currency.tryLira.minorUnitsPerWhole).round();
    return Money(minorUnits, Currency.tryLira);
  }

  final int minorUnits;
  final Currency currency;

  bool get isNegative => minorUnits < 0;
  bool get isZero => minorUnits == 0;
  bool get isPositive => minorUnits > 0;

  Money operator +(Money other) {
    _requireSameCurrency(other);
    return Money(minorUnits + other.minorUnits, currency);
  }

  Money operator -(Money other) {
    _requireSameCurrency(other);
    return Money(minorUnits - other.minorUnits, currency);
  }

  Money operator *(int factor) => Money(minorUnits * factor, currency);

  Money operator -() => Money(-minorUnits, currency);

  @override
  int compareTo(Money other) {
    _requireSameCurrency(other);
    return minorUnits.compareTo(other.minorUnits);
  }

  bool operator <(Money other) => compareTo(other) < 0;
  bool operator <=(Money other) => compareTo(other) <= 0;
  bool operator >(Money other) => compareTo(other) > 0;
  bool operator >=(Money other) => compareTo(other) >= 0;

  /// This amount scaled by the exact rational `numerator / denominator`
  /// (e.g. a discount percentage), rounded half away from zero to the
  /// nearest minor unit. [denominator] must be positive.
  Money scaledBy(int numerator, int denominator) {
    return Money(
      MoneyRounding.halfAwayFromZero(minorUnits * numerator, denominator),
      currency,
    );
  }

  void _requireSameCurrency(Money other) {
    if (currency != other.currency) {
      throw CurrencyMismatchViolation(
        expectedCurrencyCode: currency.isoCode,
        actualCurrencyCode: other.currency.isoCode,
      );
    }
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is Money &&
            other.minorUnits == minorUnits &&
            other.currency == currency);
  }

  @override
  int get hashCode => Object.hash(minorUnits, currency);

  @override
  String toString() {
    final digits = currency.minorUnitDigits;
    final whole = minorUnits ~/ currency.minorUnitsPerWhole;
    final fraction = minorUnits.abs() % currency.minorUnitsPerWhole;
    return '${currency.isoCode} $whole.${fraction.toString().padLeft(digits, '0')}';
  }
}
