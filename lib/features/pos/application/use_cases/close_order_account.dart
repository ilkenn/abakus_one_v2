import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../orders/domain/models/order_actor.dart';
import '../../data/closure_audit_entry_repository.dart';
import '../../domain/audit/closure_audit_entry.dart';
import '../../domain/audit/closure_audit_event_type.dart';
import '../../domain/models/order_closure.dart';
import '../../domain/models/order_closure_lifecycle_status.dart';
import '../../domain/models/payment_session.dart';
import '../../domain/models/payment_session_status.dart';

/// Closes an [OrderClosure] once its [PaymentSession] has completed.
///
/// Picks [OrderClosureLifecycleStatus.closed] the first time
/// ([OrderClosure.reopenCount] `== 0`) or
/// [OrderClosureLifecycleStatus.reclosed] any time after — the same use
/// case handles both, rather than a separate `RecloseOrderAccount`, since
/// the only difference is which terminal-ish status is reached (see
/// `docs/decisions.md` ADR-012 for why a second, near-duplicate use case
/// was deliberately not added).
///
/// Appends a [ClosureAuditEntry] ([ClosureAuditEventType.orderClosed] or
/// [ClosureAuditEventType.orderReclosed]) as part of the same call — every
/// closure/reopen/correction use case in this sprint owns writing its own
/// audit entry, not left to a caller to remember.
class CloseOrderAccount {
  const CloseOrderAccount({
    required Clock clock,
    required ClosureAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _auditRepository = auditRepository;

  final Clock _clock;
  final ClosureAuditEntryRepository _auditRepository;

  /// Throws [StaleRevisionViolation] if [expectedRevision] doesn't match
  /// [closure]'s current revision, [PaymentSessionNotReadyViolation] if
  /// [paymentSession] is not [PaymentSessionStatus.completed], or
  /// [InvalidOrderClosureTransitionViolation] if [closure]'s current
  /// status can't reach the target closed/reclosed status.
  Future<OrderClosure> call({
    required OrderClosure closure,
    required PaymentSession paymentSession,
    required int expectedRevision,
    required String closedByStaffId,
  }) async {
    if (expectedRevision != closure.revision) {
      throw StaleRevisionViolation(
        expectedRevision: expectedRevision,
        actualRevision: closure.revision,
      );
    }
    if (paymentSession.status != PaymentSessionStatus.completed) {
      throw PaymentSessionNotReadyViolation(
        remainingMinorUnits: paymentSession.remainingAmount.minorUnits,
      );
    }

    final targetStatus = closure.reopenCount == 0
        ? OrderClosureLifecycleStatus.closed
        : OrderClosureLifecycleStatus.reclosed;
    if (!OrderClosureLifecycleTransitions.canTransition(
      closure.lifecycleStatus,
      targetStatus,
    )) {
      throw InvalidOrderClosureTransitionViolation(
        fromStatusName: closure.lifecycleStatus.name,
        toStatusName: targetStatus.name,
      );
    }

    final now = _clock.now();
    final updated = closure.copyWith(
      lifecycleStatus: targetStatus,
      closedAt: now,
      closedByStaffId: closedByStaffId,
      paymentSessionId: paymentSession.id,
      revision: closure.revision + 1,
    );

    await _auditRepository.appendEvent(
      closure.orderId,
      ClosureAuditEntry(
        id: '${closure.closureId}-${updated.revision}',
        type: targetStatus == OrderClosureLifecycleStatus.closed
            ? ClosureAuditEventType.orderClosed
            : ClosureAuditEventType.orderReclosed,
        description: targetStatus == OrderClosureLifecycleStatus.closed
            ? 'Order closed'
            : 'Order reclosed',
        actor: OrderActor.staff,
        timestamp: now,
        previousValue: closure.lifecycleStatus.name,
        newValue: targetStatus.name,
      ),
    );

    return updated;
  }
}
