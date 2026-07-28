import '../../../../core/errors/business_rule_violation.dart';
import '../../domain/models/payment_session.dart';
import '../../domain/models/payment_session_status.dart';

/// Cancels a [PaymentSession] — a cashier-initiated "give up on this
/// payment attempt," distinct from `failed` (a completion attempt that
/// didn't pass validation) and from `VoidPayment` (correcting an
/// already-*completed* session's settled split).
class CancelPaymentSession {
  const CancelPaymentSession();

  /// Throws [InvalidPaymentSessionStatusTransitionViolation] if [session]
  /// is already `completed`/`cancelled` (cancel is not idempotent —
  /// cancelling twice, or cancelling a completed session, is a caller
  /// error to surface, not silently ignore).
  PaymentSession call({
    required PaymentSession session,
    required int expectedRevision,
  }) {
    if (expectedRevision != session.revision) {
      throw StaleRevisionViolation(
        expectedRevision: expectedRevision,
        actualRevision: session.revision,
      );
    }
    if (!PaymentSessionStatusTransitions.canTransition(
      session.status,
      PaymentSessionStatus.cancelled,
    )) {
      throw InvalidPaymentSessionStatusTransitionViolation(
        fromStatusName: session.status.name,
        toStatusName: PaymentSessionStatus.cancelled.name,
      );
    }

    return session.copyWith(
      status: PaymentSessionStatus.cancelled,
      revision: session.revision + 1,
    );
  }
}
