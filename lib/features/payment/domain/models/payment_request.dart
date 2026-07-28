import '../../../../shared/models/money.dart';
import 'payment_method_snapshot.dart';

/// A request to a [PaymentProviderAdapter] to process one payment —
/// [amount] is always [Money] (never `double`), and [method] carries the
/// full [PaymentMethodSnapshot] (not just a provider id) so an adapter has
/// everything it needs (display name, capability flags at capture time)
/// without a second lookup.
class PaymentRequest {
  final String orderId;
  final Money amount;
  final PaymentMethodSnapshot method;
  final Map<String, dynamic> metadata;

  const PaymentRequest({
    required this.orderId,
    required this.amount,
    required this.method,
    this.metadata = const {},
  });
}
