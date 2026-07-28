import '../../data/adapters/adyen_adapter.dart';
import '../../data/adapters/edenred_adapter.dart';
import '../../data/adapters/iyzico_adapter.dart';
import '../../data/adapters/metropol_card_adapter.dart';
import '../../data/adapters/multinet_adapter.dart';
import '../../data/adapters/ode_al_adapter.dart';
import '../../data/adapters/payment_provider_adapter.dart';
import '../../data/adapters/pluxee_adapter.dart';
import '../../data/adapters/setcard_adapter.dart';
import '../../data/adapters/stripe_adapter.dart';
import '../../../../shared/models/money.dart';
import '../../domain/models/payment_enums.dart';
import '../../domain/models/payment_method_snapshot.dart';
import '../../domain/models/payment_provider_id.dart';
import '../../domain/models/payment_request.dart';
import '../../domain/models/payment_result.dart';

/// Routes a [PaymentRequest] to the [PaymentProviderAdapter] matching
/// `request.method.providerId` — **not** the payment method itself
/// (`docs/decisions.md` ADR-012's Payment Method / Payment Provider
/// split). A manually recorded method (cash, bank transfer, gift voucher)
/// has no [PaymentProviderId] at all and must never reach this service —
/// `AddPaymentSplit` branches before ever constructing a [PaymentRequest]
/// for one. Calling this with a providerless method is treated as a
/// caller error, reported as a failed [PaymentResult] rather than a
/// thrown exception, since this is an infrastructure-orchestration
/// boundary, not a domain invariant.
class PaymentService {
  final Map<PaymentProviderId, PaymentProviderAdapter> _adapters;

  PaymentService()
      : _adapters = {
          PaymentProviderId.iyzico: IyzicoPaymentAdapter(),
          PaymentProviderId.stripe: StripePaymentAdapter(),
          PaymentProviderId.adyen: AdyenPaymentAdapter(),
          PaymentProviderId.odeal: OdeAlPaymentAdapter(),
          PaymentProviderId.pluxee: PluxeePaymentAdapter(),
          PaymentProviderId.multinet: MultinetPaymentAdapter(),
          PaymentProviderId.setcard: SetcardPaymentAdapter(),
          PaymentProviderId.edenred: EdenredPaymentAdapter(),
          PaymentProviderId.metropolCard: MetropolCardPaymentAdapter(),
        };

  Future<PaymentResult> executePayment(PaymentRequest request) async {
    final providerId = request.method.providerId;
    if (providerId == null) {
      return PaymentResult(
        transactionId: '',
        status: PaymentStatus.failed,
        errorMessage:
            '${request.method.displayName} manuel kaydedilen bir yöntemdir, '
            'bir ödeme sağlayıcısına yönlendirilemez.',
      );
    }
    final adapter = _adapters[providerId];
    if (adapter == null) {
      return PaymentResult(
        transactionId: '',
        status: PaymentStatus.failed,
        errorMessage: '${providerId.name} için bir ödeme adaptörü bulunamadı.',
      );
    }
    return adapter.processPayment(request);
  }

  /// Routes a refund/reversal request to the adapter matching
  /// [method]'s provider — the counterpart to [executePayment] for
  /// `VoidPayment`. Same providerless-method handling: never called for a
  /// manual method by any caller in this codebase, but fails cleanly
  /// (not a thrown exception) if it ever is.
  Future<PaymentResult> executeRefund({
    required PaymentMethodSnapshot method,
    required String transactionId,
    required Money amount,
  }) async {
    final providerId = method.providerId;
    if (providerId == null) {
      return PaymentResult(
        transactionId: '',
        status: PaymentStatus.failed,
        errorMessage:
            '${method.displayName} manuel kaydedilen bir yöntemdir, '
            'bir ödeme sağlayıcısına yönlendirilemez.',
      );
    }
    final adapter = _adapters[providerId];
    if (adapter == null) {
      return PaymentResult(
        transactionId: '',
        status: PaymentStatus.failed,
        errorMessage: '${providerId.name} için bir ödeme adaptörü bulunamadı.',
      );
    }
    return adapter.refundPayment(transactionId, amount);
  }
}
