import '../../core/errors/business_rule_violation.dart';
import 'currency.dart';
import 'exchange_rate_policy.dart';
import 'money.dart';
import 'money_rounding.dart';

/// A frozen, point-in-time foreign-currency-to-TRY exchange rate, captured
/// at the moment it's used (a payment, an informational receipt equivalent)
/// — never recomputed later. Approved multi-currency payment decision:
/// `acceptanceRate = marketSellingRate - fixedMargin`, where
/// [marketSellingRate] is the source currency's daily market selling rate
/// against TRY.
///
/// Every field this app cares about for "what rate did we actually use and
/// why" is captured here, so a historical payment or receipt never needs
/// to re-derive its own numbers from a policy/provider that may have since
/// changed — see [capture]'s doc comment.
class ExchangeRateSnapshot {
  const ExchangeRateSnapshot._({
    required this.sourceCurrency,
    required this.targetCurrency,
    required this.marketSellingRate,
    required this.fixedMargin,
    required this.acceptanceRate,
    required this.rateTimestamp,
    required this.rateSource,
  });

  /// The foreign currency this rate converts *from*.
  final Currency sourceCurrency;

  /// The currency this rate converts *to* — always
  /// [Currency.accountingCurrency] in this app (see the approved decision:
  /// "Accounting and menu pricing remain TRY-based"). Modeled as an
  /// explicit field rather than assumed implicitly, so a snapshot is
  /// self-describing without the reader having to know that rule.
  final Currency targetCurrency;

  /// [sourceCurrency]'s daily market selling rate against
  /// [Currency.accountingCurrency], expressed as a [Money] amount (in that
  /// accounting currency) per one whole unit of [sourceCurrency] (e.g.
  /// 47.00 TRY per 1 EUR).
  final Money marketSellingRate;

  /// The business's fixed margin subtracted from [marketSellingRate] to
  /// reach [acceptanceRate] — captured per-snapshot (not read live from
  /// [ExchangeRatePolicy] at conversion time) so a change to the policy's
  /// default margin never alters a historical snapshot's own math.
  final Money fixedMargin;

  /// `marketSellingRate - fixedMargin` — the rate actually applied to
  /// convert a foreign-currency payment amount into TRY. Always positive
  /// (see [capture]).
  final Money acceptanceRate;

  /// When this rate was captured.
  final DateTime rateTimestamp;

  /// Free-text provenance of [marketSellingRate] (e.g. a bank name, "manual
  /// entry") — no real rate provider is integrated yet (see
  /// `ExchangeRateProvider`), so this is deliberately not a closed enum.
  final String rateSource;

  /// Captures a new snapshot, computing and validating [acceptanceRate].
  ///
  /// Throws [UnsupportedExchangeRateCurrencyViolation] if [sourceCurrency]
  /// is the accounting currency (nothing to convert) or if
  /// [marketSellingRate]/[fixedMargin] aren't themselves denominated in it.
  /// Throws [CurrencyNotAcceptedViolation] if `sourceCurrency
  /// .isAcceptedByBusiness` is `false` — a rate is never captured for a
  /// currency the business doesn't currently accept. Throws
  /// [NonPositiveAcceptanceRateViolation] if the computed acceptance rate
  /// would be zero or negative (a market rate that doesn't clear the fixed
  /// margin is refused outright, never silently accepted at a worse rate).
  factory ExchangeRateSnapshot.capture({
    required Currency sourceCurrency,
    required Money marketSellingRate,
    Money? fixedMargin,
    required DateTime rateTimestamp,
    required String rateSource,
  }) {
    final accountingCurrency = Currency.accountingCurrency;
    if (sourceCurrency == accountingCurrency) {
      throw UnsupportedExchangeRateCurrencyViolation(
        sourceCurrencyCode: sourceCurrency.isoCode,
        targetCurrencyCode: accountingCurrency.isoCode,
      );
    }
    if (!sourceCurrency.isAcceptedByBusiness) {
      throw CurrencyNotAcceptedViolation(currencyCode: sourceCurrency.isoCode);
    }
    if (marketSellingRate.currency != accountingCurrency) {
      throw UnsupportedExchangeRateCurrencyViolation(
        sourceCurrencyCode: marketSellingRate.currency.isoCode,
        targetCurrencyCode: accountingCurrency.isoCode,
      );
    }
    final margin = fixedMargin ?? ExchangeRatePolicy.fixedMargin;
    if (margin.currency != accountingCurrency) {
      throw UnsupportedExchangeRateCurrencyViolation(
        sourceCurrencyCode: margin.currency.isoCode,
        targetCurrencyCode: accountingCurrency.isoCode,
      );
    }
    final acceptance = marketSellingRate - margin;
    if (!acceptance.isPositive) {
      throw NonPositiveAcceptanceRateViolation(
        marketSellingRateMinorUnits: marketSellingRate.minorUnits,
        fixedMarginMinorUnits: margin.minorUnits,
      );
    }
    return ExchangeRateSnapshot._(
      sourceCurrency: sourceCurrency,
      targetCurrency: accountingCurrency,
      marketSellingRate: marketSellingRate,
      fixedMargin: margin,
      acceptanceRate: acceptance,
      rateTimestamp: rateTimestamp,
      rateSource: rateSource,
    );
  }

  /// Converts [foreignAmount] (must be in [sourceCurrency]) to the
  /// accounting currency using [acceptanceRate] — Round Half Away From
  /// Zero on minor units, per this app's one rounding policy
  /// (`MoneyRounding`). Used by a foreign-currency `PaymentSplit`.
  Money convertToTry(Money foreignAmount) {
    if (foreignAmount.currency != sourceCurrency) {
      throw CurrencyMismatchViolation(
        expectedCurrencyCode: sourceCurrency.isoCode,
        actualCurrencyCode: foreignAmount.currency.isoCode,
      );
    }
    final minorUnitsTry = MoneyRounding.halfAwayFromZero(
      foreignAmount.minorUnits * acceptanceRate.minorUnits,
      sourceCurrency.minorUnitsPerWhole,
    );
    return Money(minorUnitsTry, targetCurrency);
  }

  /// The inverse of [convertToTry]: converts [accountingAmount] (must be
  /// in [targetCurrency]) into [sourceCurrency] using [acceptanceRate] —
  /// the computation a "estimated EUR/USD equivalent" line on a receipt or
  /// a cashier's live display uses. Also Round Half Away From Zero.
  Money convertFromTry(Money accountingAmount) {
    if (accountingAmount.currency != targetCurrency) {
      throw CurrencyMismatchViolation(
        expectedCurrencyCode: targetCurrency.isoCode,
        actualCurrencyCode: accountingAmount.currency.isoCode,
      );
    }
    final minorUnitsForeign = MoneyRounding.halfAwayFromZero(
      accountingAmount.minorUnits * sourceCurrency.minorUnitsPerWhole,
      acceptanceRate.minorUnits,
    );
    return Money(minorUnitsForeign, sourceCurrency);
  }

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is ExchangeRateSnapshot &&
            other.sourceCurrency == sourceCurrency &&
            other.targetCurrency == targetCurrency &&
            other.marketSellingRate == marketSellingRate &&
            other.fixedMargin == fixedMargin &&
            other.acceptanceRate == acceptanceRate &&
            other.rateTimestamp == rateTimestamp &&
            other.rateSource == rateSource);
  }

  @override
  int get hashCode => Object.hash(
        sourceCurrency,
        targetCurrency,
        marketSellingRate,
        fixedMargin,
        acceptanceRate,
        rateTimestamp,
        rateSource,
      );
}
