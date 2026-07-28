import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../orders/domain/models/order_actor.dart';
import '../../../orders/domain/models/order_id.dart';
import '../../../orders/domain/payment/payment_split.dart';
import '../../../payment/domain/models/payment_enums.dart';
import '../../../payment/presentation/services/payment_service.dart';
import '../../data/closure_audit_entry_repository.dart';
import '../../domain/audit/closure_audit_entry.dart';
import '../../domain/audit/closure_audit_event_type.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/payments/payment_void.dart';
import '../../domain/payments/payment_void_status.dart';

/// Voids an already-*completed* [PaymentSplit] — never mutates the split
/// itself (`docs/decisions.md` ADR-012's append-only-financial-record
/// principle). The original split remains exactly as recorded; this
/// produces a separate, linked [PaymentVoid] record.
///
/// A manually recorded method (no provider) completes synchronously —
/// there's no external system to reverse anything with. A provider-routed
/// split's reversal is attempted via [PaymentService.executeRefund]; the
/// [PaymentVoid] lands on [PaymentVoidStatus.completed] only if that
/// succeeds, [PaymentVoidStatus.rejected] otherwise (which, since no real
/// provider integration exists this sprint, is what every provider-routed
/// void actually resolves to today — an honest limitation, not a bug).
class VoidPayment {
  const VoidPayment({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required ClosureAuditEntryRepository auditRepository,
    required PaymentService paymentService,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _auditRepository = auditRepository,
        _paymentService = paymentService;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final ClosureAuditEntryRepository _auditRepository;
  final PaymentService _paymentService;

  /// Throws [AuthorizationDeniedViolation] if the policy denies the
  /// action. Never throws for a provider reversal failure — that's
  /// reported as [PaymentVoidStatus.rejected] on the returned
  /// [PaymentVoid], not an exception, since a void attempt that didn't
  /// succeed is a valid, expected outcome to show the cashier, not a
  /// programming error.
  Future<PaymentVoid> call({
    required OrderId orderId,
    required PaymentSplit split,
    required String reason,
    required String requestedByStaffId,
  }) async {
    final authResult = await _authorizationPolicy.authorize(
      action: PosAuthorizedAction.voidPayment,
      actorStaffId: requestedByStaffId,
      context: {'splitId': split.id},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(
        actionName: PosAuthorizedAction.voidPayment.name,
      );
    }

    final now = _clock.now();
    var result = PaymentVoid(
      id: '${split.id}-void',
      originalSplitId: split.id,
      reason: reason,
      requestedByStaffId: requestedByStaffId,
      requestedAt: now,
      status: PaymentVoidStatus.pending,
    );

    if (split.methodSnapshot.providerId != null) {
      final providerResult = await _paymentService.executeRefund(
        method: split.methodSnapshot,
        transactionId: split.methodSnapshot.transactionReference ?? split.id,
        amount: split.amount,
      );
      result = result.copyWith(
        status: providerResult.status == PaymentStatus.success
            ? PaymentVoidStatus.completed
            : PaymentVoidStatus.rejected,
        providerReversalReference: providerResult.transactionId.isEmpty
            ? null
            : providerResult.transactionId,
      );
    } else {
      result = result.copyWith(status: PaymentVoidStatus.completed);
    }

    await _auditRepository.appendEvent(
      orderId,
      ClosureAuditEntry(
        id: '${result.id}-audit',
        type: ClosureAuditEventType.paymentVoided,
        description: 'Payment voided: $reason',
        actor: OrderActor.staff,
        timestamp: now,
        newValue: result.status.name,
      ),
    );

    return result;
  }
}
