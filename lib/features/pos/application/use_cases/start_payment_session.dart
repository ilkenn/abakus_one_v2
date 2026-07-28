import '../../../../core/utils/clock.dart';
import '../../../../shared/models/money.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../domain/models/payment_session.dart';
import '../../domain/models/payment_session_status.dart';

/// Starts a new [PaymentSession] for an already-submitted [Order] —
/// per the approved architecture, payment collection begins only after
/// `SubmitPosOrder` has produced a real `Order`/`OrderId`
/// (`docs/decisions.md` ADR-012).
///
/// [sessionId] is externally supplied — this use case never generates one,
/// matching every other identity in this codebase.
class StartPaymentSession {
  const StartPaymentSession({required Clock clock}) : _clock = clock;

  final Clock _clock;

  PaymentSession call({
    required String sessionId,
    required OrderId orderId,
    required Money totalAmount,
  }) {
    return PaymentSession(
      id: sessionId,
      orderId: orderId,
      totalAmount: totalAmount,
      status: PaymentSessionStatus.collecting,
      createdAt: _clock.now(),
      revision: 1,
    );
  }
}
