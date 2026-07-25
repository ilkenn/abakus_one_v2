import 'payment_enums.dart';

class PaymentResult {
  final String transactionId;
  final PaymentStatus status;
  final String errorMessage;
  final Map<String, dynamic> rawResponse;

  const PaymentResult({
    required this.transactionId,
    required this.status,
    required this.errorMessage,
    this.rawResponse = const {},
  });
}
