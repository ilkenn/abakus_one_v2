import '../../../../shared/models/money.dart';
import '../../domain/models/payment_enums.dart';
import '../../domain/models/payment_request.dart';
import '../../domain/models/payment_result.dart';
import 'payment_provider_adapter.dart';

class SetcardPaymentAdapter implements PaymentProviderAdapter {
  @override
  Future<PaymentResult> processPayment(PaymentRequest request) async {
    return const PaymentResult(
      transactionId: '',
      status: PaymentStatus.notConfigured,
      errorMessage: 'Setcard entegrasyonu henüz yapılandırılmadı.',
    );
  }

  @override
  Future<PaymentResult> refundPayment(
    String transactionId,
    Money amount,
  ) async {
    return const PaymentResult(
      transactionId: '',
      status: PaymentStatus.notConfigured,
      errorMessage: 'Setcard entegrasyonu henüz yapılandırılmadı.',
    );
  }
}
