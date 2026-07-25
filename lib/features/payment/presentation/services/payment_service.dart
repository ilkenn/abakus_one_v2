import '../../data/adapters/edenred_adapter.dart';
import '../../data/adapters/multinet_adapter.dart';
import '../../data/adapters/ode_al_adapter.dart';
import '../../data/adapters/payment_provider_adapter.dart';
import '../../data/adapters/pluxee_adapter.dart';
import '../../data/adapters/setcard_adapter.dart';
import '../../domain/models/payment_enums.dart';
import '../../domain/models/payment_request.dart';
import '../../domain/models/payment_result.dart';

class PaymentService {
  final Map<PaymentMethodType, PaymentProviderAdapter> _adapters;

  PaymentService()
      : _adapters = {
          PaymentMethodType.odeAl: OdeAlPaymentAdapter(),
          PaymentMethodType.pluxee: PluxeePaymentAdapter(),
          PaymentMethodType.edenred: EdenredPaymentAdapter(),
          PaymentMethodType.multinet: MultinetPaymentAdapter(),
          PaymentMethodType.setcard: SetcardPaymentAdapter(),
        };

  Future<PaymentResult> executePayment(PaymentRequest request) async {
    final adapter = _adapters[request.paymentMethod];
    if (adapter == null) {
      return PaymentResult(
        transactionId: '',
        status: PaymentStatus.failed,
        errorMessage:
            '${request.paymentMethod.name} için bir ödeme adaptörü bulunamadı.',
      );
    }
    return adapter.processPayment(request);
  }
}
