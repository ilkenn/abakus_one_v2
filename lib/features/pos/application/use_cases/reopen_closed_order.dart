import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../orders/domain/models/order_actor.dart';
import '../../data/closure_audit_entry_repository.dart';
import '../../domain/audit/closure_audit_entry.dart';
import '../../domain/audit/closure_audit_event_type.dart';
import '../../domain/authorization/approval_result.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/models/order_closure.dart';
import '../../domain/models/order_closure_lifecycle_status.dart';

/// Reopens a closed/reclosed [OrderClosure] — requires a [reason], the
/// acting staff member, an authorization check, and (if the policy says
/// so) a granted manager [ApprovalResult]. Every past closure/audit
/// record remains untouched; this only appends a new revision and a new
/// [ClosureAuditEntry], never rewrites history.
class ReopenClosedOrder {
  const ReopenClosedOrder({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required ClosureAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final ClosureAuditEntryRepository _auditRepository;

  /// Throws [StaleRevisionViolation], [InvalidOrderClosureTransitionViolation]
  /// if [closure] isn't currently `closed`/`reclosed`, or
  /// [AuthorizationDeniedViolation] if the policy denies the action or
  /// requires an [ApprovalResult] that wasn't granted.
  Future<OrderClosure> call({
    required OrderClosure closure,
    required int expectedRevision,
    required String reason,
    required String performedByStaffId,
    ApprovalResult? approval,
  }) async {
    if (expectedRevision != closure.revision) {
      throw StaleRevisionViolation(
        expectedRevision: expectedRevision,
        actualRevision: closure.revision,
      );
    }
    if (!OrderClosureLifecycleTransitions.canTransition(
      closure.lifecycleStatus,
      OrderClosureLifecycleStatus.reopened,
    )) {
      throw InvalidOrderClosureTransitionViolation(
        fromStatusName: closure.lifecycleStatus.name,
        toStatusName: OrderClosureLifecycleStatus.reopened.name,
      );
    }

    final authResult = await _authorizationPolicy.authorize(
      action: PosAuthorizedAction.reopenOrder,
      actorStaffId: performedByStaffId,
      context: {'closureId': closure.closureId, 'reason': reason},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(
        actionName: PosAuthorizedAction.reopenOrder.name,
      );
    }
    if (authResult.requiresManagerApproval && approval?.granted != true) {
      throw AuthorizationDeniedViolation(
        actionName: '${PosAuthorizedAction.reopenOrder.name} (manager approval required)',
      );
    }

    final now = _clock.now();
    final updated = closure.copyWith(
      lifecycleStatus: OrderClosureLifecycleStatus.reopened,
      reopenCount: closure.reopenCount + 1,
      revision: closure.revision + 1,
    );

    await _auditRepository.appendEvent(
      closure.orderId,
      ClosureAuditEntry(
        id: '${closure.closureId}-${updated.revision}',
        type: ClosureAuditEventType.orderReopened,
        description: 'Order reopened: $reason',
        actor: OrderActor.staff,
        timestamp: now,
        previousValue: closure.lifecycleStatus.name,
        newValue: OrderClosureLifecycleStatus.reopened.name,
      ),
    );

    return updated;
  }
}
