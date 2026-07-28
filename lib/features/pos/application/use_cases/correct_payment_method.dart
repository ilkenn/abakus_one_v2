import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../orders/domain/models/order_actor.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../orders/domain/payment/payment_split.dart';
import '../../../payment/domain/models/payment_method.dart';
import '../../../payment/domain/models/payment_method_snapshot.dart';
import '../../data/closure_audit_entry_repository.dart';
import '../../domain/audit/closure_audit_entry.dart';
import '../../domain/audit/closure_audit_event_type.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/payments/payment_correction.dart';
import '../../domain/payments/payment_correction_type.dart';
import '../../domain/payments/payment_void.dart';
import '../identity/payment_split_id_generator.dart';
import 'void_payment.dart';

/// The result of [CorrectPaymentMethod] — the caller (a future closed-
/// account correction flow) needs all three to update its own state: the
/// [void_] record for the original split, the brand-new [replacementSplit]
/// to record in the original split's place, and the [correction] linking
/// them.
class PaymentMethodCorrectionResult {
  const PaymentMethodCorrectionResult({
    required this.correction,
    required this.replacementSplit,
    required this.void_,
  });

  final PaymentCorrection correction;
  final PaymentSplit replacementSplit;
  final PaymentVoid void_;
}

/// Corrects a payment recorded under the wrong method — the only
/// [PaymentCorrectionType] any use case actually produces this sprint
/// (`paymentMethodCorrection`). Composed from [VoidPayment] (the original
/// split is voided, never mutated) plus a freshly recorded replacement
/// split under [newMethod] — **the same amount**, since this corrects
/// *which* method was used, not *how much* was paid
/// (`docs/decisions.md` ADR-012: "if the financial total doesn't change,
/// no new collection is made").
class CorrectPaymentMethod {
  const CorrectPaymentMethod({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required ClosureAuditEntryRepository auditRepository,
    required VoidPayment voidPayment,
    required PaymentSplitIdGenerator splitIdGenerator,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _auditRepository = auditRepository,
        _voidPayment = voidPayment,
        _splitIdGenerator = splitIdGenerator;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final ClosureAuditEntryRepository _auditRepository;
  final VoidPayment _voidPayment;
  final PaymentSplitIdGenerator _splitIdGenerator;

  /// Throws [AuthorizationDeniedViolation] if the policy denies the
  /// action.
  Future<PaymentMethodCorrectionResult> call({
    required OrderId orderId,
    required PaymentSplit originalSplit,
    required PaymentMethod newMethod,
    required String reason,
    required String correctedByStaffId,
  }) async {
    final authResult = await _authorizationPolicy.authorize(
      action: PosAuthorizedAction.correctPayment,
      actorStaffId: correctedByStaffId,
      context: {'splitId': originalSplit.id},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(
        actionName: PosAuthorizedAction.correctPayment.name,
      );
    }

    final void_ = await _voidPayment(
      orderId: orderId,
      split: originalSplit,
      reason: reason,
      requestedByStaffId: correctedByStaffId,
    );

    final newSnapshot = PaymentMethodSnapshot.capture(newMethod);
    final replacementSplit = originalSplit.isForeignCurrency
        ? PaymentSplit.foreignCurrency(
            id: _splitIdGenerator.nextSplitId(),
            methodSnapshot: newSnapshot,
            amount: originalSplit.amount,
            exchangeRate: originalSplit.exchangeRate!,
          )
        : PaymentSplit.tryLira(
            id: _splitIdGenerator.nextSplitId(),
            methodSnapshot: newSnapshot,
            amount: originalSplit.amount,
          );

    final now = _clock.now();
    final correction = PaymentCorrection(
      id: '${originalSplit.id}-correction',
      correctionType: PaymentCorrectionType.paymentMethodCorrection,
      originalPaymentId: originalSplit.id,
      replacementPaymentId: replacementSplit.id,
      correctionReferenceId: '${originalSplit.id}-correction-ref',
      previousPaymentMethodSnapshot: originalSplit.methodSnapshot,
      newPaymentMethodSnapshot: newSnapshot,
      correctionReason: reason,
      correctedByStaffId: correctedByStaffId,
      correctedAt: now,
      providerReversalReference: void_.providerReversalReference,
    );

    await _auditRepository.appendEvent(
      orderId,
      ClosureAuditEntry(
        id: '${correction.id}-audit',
        type: ClosureAuditEventType.paymentMethodCorrected,
        description: 'Payment method corrected: $reason',
        actor: OrderActor.staff,
        timestamp: now,
        previousValue: originalSplit.methodSnapshot.paymentMethodId,
        newValue: newSnapshot.paymentMethodId,
      ),
    );

    return PaymentMethodCorrectionResult(
      correction: correction,
      replacementSplit: replacementSplit,
      void_: void_,
    );
  }
}
