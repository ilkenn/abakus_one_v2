import 'payment_enums.dart';

class PaymentRequest {
  final String orderId;
  final double amount;
  final PaymentMethodType paymentMethod;
  final Map<String, dynamic> metadata;

  const PaymentRequest({
    required this.orderId,
    required this.amount,
    required this.paymentMethod,
    this.metadata = const {},
  });
}
