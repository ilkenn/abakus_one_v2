import '../../../../core/errors/business_rule_violation.dart';
import '../../../payment/domain/models/payment_enums.dart';
import '../../../payment/domain/models/payment_request.dart';
import '../../../payment/presentation/services/payment_service.dart';
import '../../domain/authorization/approval_result.dart';
import '../../domain/models/payment_session.dart';
import '../../domain/models/payment_session_status.dart';

/// Explicitly completes a [PaymentSession] — required by the approved
/// architecture decision (completion is **never** automatic just because
/// `remainingAmount` hits zero; that only moves the session to
/// `readyToComplete`, a distinct step from actually completing).
///
/// Validates, in order:
/// 1. [expectedRevision] matches the session's current revision
///    (optimistic-concurrency guard — [StaleRevisionViolation]).
/// 2. `remainingAmount` is zero ([PaymentSessionNotReadyViolation]).
/// 3. Every split whose method requires a reference number has one
///    ([MissingPaymentReferenceViolation]).
/// 4. Every split whose method requires approval has a granted
///    [ApprovalResult] in [approvals] ([PaymentMethodNotApprovedViolation]).
/// 5. Every split whose method routes through a provider has a
///    `PaymentStatus.success` result from [PaymentService]
///    ([ProviderTransactionNotSuccessfulViolation] — since no real
///    provider integration exists this sprint, every provider-routed
///    split always fails this check today; only manual/no-provider
///    methods can complete a session end to end right now, which is the
///    honest current capability, not a bug).
///
/// The `completing` state itself is owned by the controller (sets it
/// before calling this, `completed`/`failure` after — mirrors
/// `SubmitPosOrder`/`PosOrderSessionController`'s existing split, Phase 3
/// Sprint 3B), not this use case.
class CompletePaymentSession {
  const CompletePaymentSession({required PaymentService paymentService})
      : _paymentService = paymentService;

  final PaymentService _paymentService;

  Future<PaymentSession> call({
    required PaymentSession session,
    required int expectedRevision,
    Map<String, ApprovalResult> approvals = const {},
  }) async {
    if (expectedRevision != session.revision) {
      throw StaleRevisionViolation(
        expectedRevision: expectedRevision,
        actualRevision: session.revision,
      );
    }
    if (!session.remainingAmount.isZero) {
      throw PaymentSessionNotReadyViolation(
        remainingMinorUnits: session.remainingAmount.minorUnits,
      );
    }

    for (final split in session.splits) {
      final snapshot = split.methodSnapshot;

      if (snapshot.requiresReferenceNumberAtCapture &&
          (snapshot.transactionReference == null ||
              snapshot.transactionReference!.isEmpty)) {
        throw MissingPaymentReferenceViolation(methodId: snapshot.paymentMethodId);
      }

      if (snapshot.requiresApprovalAtCapture &&
          approvals[split.id]?.granted != true) {
        throw PaymentMethodNotApprovedViolation(methodId: snapshot.paymentMethodId);
      }

      if (snapshot.providerId != null) {
        final result = await _paymentService.executePayment(
          PaymentRequest(
            orderId: session.orderId.value,
            amount: split.amount,
            method: snapshot,
          ),
        );
        if (result.status != PaymentStatus.success) {
          throw ProviderTransactionNotSuccessfulViolation(
            splitId: split.id,
            statusName: result.status.name,
          );
        }
      }
    }

    return session.copyWith(
      status: PaymentSessionStatus.completed,
      revision: session.revision + 1,
    );
  }
}
