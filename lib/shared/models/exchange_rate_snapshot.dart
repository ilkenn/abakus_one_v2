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

  /// The currency this rate converts *to* — always [Currency.tryLira] in
  /// this app (see the approved decision: "Accounting and menu pricing
  /// remain TRY-based"). Modeled as an explicit field rather than assumed
  /// implicitly, so a snapshot is self-describing without the reader
  /// having to know that rule.
  final Currency targetCurrency;

  /// [sourceCurrency]'s daily market selling rate against TRY, expressed
  /// as a TRY [Money] amount per one whole unit of [sourceCurrency] (e.g.
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
  /// [ExchangeRateProvider]), so this is deliberately not a closed enum.
  final String rateSource;

  /// Captures a new snapshot, computing and validating [acceptanceRate].
  ///
  /// Throws [UnsupportedExchangeRateCurrencyViolation] if [sourceCurrency]
  /// is TRY (nothing to convert) or if [marketSellingRate]/[fixedMargin]
  /// aren't themselves TRY-denominated. Throws
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
    if (sourceCurrency == Currency.tryLira) {
      throw UnsupportedExchangeRateCurrencyViolation(
        sourceCurrencyCode: sourceCurrency.isoCode,
        targetCurrencyCode: Currency.tryLira.isoCode,
      );
    }
    if (marketSellingRate.currency != Currency.tryLira) {
      throw UnsupportedExchangeRateCurrencyViolation(
        sourceCurrencyCode: marketSellingRate.currency.isoCode,
        targetCurrencyCode: Currency.tryLira.isoCode,
      );
    }
    final margin = fixedMargin ?? ExchangeRatePolicy.fixedMargin;
    if (margin.currency != Currency.tryLira) {
      throw UnsupportedExchangeRateCurrencyViolation(
        sourceCurrencyCode: margin.currency.isoCode,
        targetCurrencyCode: Currency.tryLira.isoCode,
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
      targetCurrency: Currency.tryLira,
      marketSellingRate: marketSellingRate,
      fixedMargin: margin,
      acceptanceRate: acceptance,
      rateTimestamp: rateTimestamp,
      rateSource: rateSource,
    );
  }

  /// Converts [foreignAmount] (must be in [sourceCurrency]) to TRY using
  /// [acceptanceRate] — Round Half Away From Zero on minor units, per this
  /// app's one rounding policy (`MoneyRounding`).
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
    return Money(minorUnitsTry, Currency.tryLira);
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

/// Source of a current [ExchangeRateSnapshot] for a foreign [Currency].
///
/// **Abstraction only** — no implementation exists this sprint. Daily rate
/// retrieval/provider integration is explicitly out of scope for Phase 3
/// Sprint 3A (see `docs/feature_status.md`); this interface exists so the
/// payment and receipt code that needs "the current rate" has one seam to
/// depend on, rather than being written against a concrete vendor that
/// doesn't exist yet.
abstract interface class ExchangeRateProvider {
  Future<ExchangeRateSnapshot> currentRate(Currency currency);
}
