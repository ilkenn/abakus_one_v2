import '../../../../core/errors/business_rule_violation.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/exchange_rate_snapshot.dart';
import '../../../../shared/models/money.dart';
import '../../../payment/domain/models/payment_enums.dart';

/// One portion of a split payment against a [PaymentIntent].
///
/// [amount] is tendered — the currency and amount the customer actually
/// paid in, which may be TRY or a foreign currency ([Currency.eur]/
/// [Currency.usd]). [settlementAmount] is always TRY: the amount this
/// split actually settles against the order's TRY balance. For a TRY
/// split the two are equal; for a foreign-currency split,
/// [settlementAmount] is [amount] converted via [exchangeRate]
/// (`ExchangeRateSnapshot.convertToTry`) — see the class's two named
/// constructors.
///
/// **Historical payments must never be recalculated using newer rates**
/// (approved multi-currency payment decision): [exchangeRate] is captured
/// once, at the moment this split is created, and [settlementAmount] is
/// computed from it then — never re-derived later from a live/updated
/// rate.
class PaymentSplit {
  const PaymentSplit._({
    required this.id,
    required this.method,
    required this.amount,
    required this.settlementAmount,
    this.exchangeRate,
  });

  /// TRY payment — no currency conversion involved. [amount] must already
  /// be TRY.
  factory PaymentSplit.tryLira({
    required String id,
    required PaymentMethodType method,
    required Money amount,
  }) {
    if (amount.currency != Currency.tryLira) {
      throw CurrencyMismatchViolation(
        expectedCurrencyCode: Currency.tryLira.isoCode,
        actualCurrencyCode: amount.currency.isoCode,
      );
    }
    return PaymentSplit._(
      id: id,
      method: method,
      amount: amount,
      settlementAmount: amount,
    );
  }

  /// Foreign-currency payment. [amount] must be in [exchangeRate]'s
  /// `sourceCurrency`; [settlementAmount] is computed immediately via
  /// `ExchangeRateSnapshot.convertToTry` and frozen from that point on.
  factory PaymentSplit.foreignCurrency({
    required String id,
    required PaymentMethodType method,
    required Money amount,
    required ExchangeRateSnapshot exchangeRate,
  }) {
    if (amount.currency == Currency.tryLira) {
      throw const ForeignCurrencyPaymentMissingExchangeRateViolation(
        currencyCode: 'TRY',
      );
    }
    return PaymentSplit._(
      id: id,
      method: method,
      amount: amount,
      settlementAmount: exchangeRate.convertToTry(amount),
      exchangeRate: exchangeRate,
    );
  }

  final String id;
  final PaymentMethodType method;

  /// The amount tendered, in whatever currency was actually paid.
  final Money amount;

  /// Always TRY — what this split settles against the order balance.
  final Money settlementAmount;

  /// The exchange-rate snapshot used to compute [settlementAmount] from
  /// [amount] — present if and only if [amount] is a foreign currency.
  final ExchangeRateSnapshot? exchangeRate;

  bool get isForeignCurrency => amount.currency != Currency.tryLira;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is PaymentSplit &&
            other.id == id &&
            other.method == method &&
            other.amount == amount &&
            other.settlementAmount == settlementAmount &&
            other.exchangeRate == exchangeRate);
  }

  @override
  int get hashCode =>
      Object.hash(id, method, amount, settlementAmount, exchangeRate);
}
