import '../../../../shared/models/exchange_rate_snapshot.dart';
import '../../../../shared/models/money.dart';
import '../../../payment/domain/models/payment_method_snapshot.dart';

/// One payment (one [PaymentSplit]) as shown on a printed receipt.
///
/// For a foreign-currency payment, approved decision: "Receipt must show
/// foreign amount, market rate, margin, acceptance rate and TRY settlement
/// amount" — [amount] (foreign) + [exchangeRate] (which itself carries
/// market rate/margin/acceptance rate) + [settlementAmount] (TRY) together
/// cover exactly that; no separate fields duplicate what [exchangeRate]
/// already carries.
///
/// [methodSnapshot] is the same frozen record the originating
/// [PaymentSplit] carries — never a live [PaymentMethod] lookup, so a
/// reprinted/duplicate receipt always reports what was true at payment
/// time (`docs/decisions.md` ADR-012).
class PaymentSummaryLine {
  const PaymentSummaryLine({
    required this.methodSnapshot,
    required this.amount,
    required this.settlementAmount,
    this.exchangeRate,
  });

  final PaymentMethodSnapshot methodSnapshot;

  /// As tendered — may be TRY or a foreign currency.
  final Money amount;

  /// Always TRY.
  final Money settlementAmount;

  /// Present if and only if [amount] was a foreign currency.
  final ExchangeRateSnapshot? exchangeRate;
}
