import '../../domain/models/payment_request.dart';
import '../../domain/models/payment_result.dart';

abstract interface class PaymentProviderAdapter {
  Future<PaymentResult> processPayment(PaymentRequest request);
  Future<PaymentResult> refundPayment(String transactionId, double amount);
}
