import '../../../../shared/models/exchange_rate_snapshot.dart';
import '../../../../shared/models/money.dart';
import '../../../payment/domain/models/payment_enums.dart';

/// One payment (one [PaymentSplit]) as shown on a printed receipt.
///
/// For a foreign-currency payment, approved decision: "Receipt must show
/// foreign amount, market rate, margin, acceptance rate and TRY settlement
/// amount" — [amount] (foreign) + [exchangeRate] (which itself carries
/// market rate/margin/acceptance rate) + [settlementAmount] (TRY) together
/// cover exactly that; no separate fields duplicate what [exchangeRate]
/// already carries.
class PaymentSummaryLine {
  const PaymentSummaryLine({
    required this.method,
    required this.amount,
    required this.settlementAmount,
    this.exchangeRate,
  });

  final PaymentMethodType method;

  /// As tendered — may be TRY or a foreign currency.
  final Money amount;

  /// Always TRY.
  final Money settlementAmount;

  /// Present if and only if [amount] was a foreign currency.
  final ExchangeRateSnapshot? exchangeRate;
}
