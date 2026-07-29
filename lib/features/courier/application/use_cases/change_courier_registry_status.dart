import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/courier_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/identity/courier.dart';
import '../../domain/identity/courier_registry_status.dart';

/// Activates/suspends/archives a [Courier] — one use case behind all
/// three registry-status transitions (mirrors `TransitionKitchenWorkItem`'s
/// "one use case, not N near-duplicates" precedent). "Archive without
/// deletion" is satisfied by reaching [CourierRegistryStatus.archived] —
/// `CourierRepository` has no delete method.
class ChangeCourierRegistryStatus {
  const ChangeCourierRegistryStatus({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CourierRepository repository,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CourierRepository _repository;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<Courier> call({
    required String courierId,
    required CourierRegistryStatus to,
    required String performedByStaffId,
    String? reason,
  }) async {
    final courier = await _repository.findById(courierId);
    if (courier == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'Courier',
        id: courierId,
      );
    }
    if (courier.status == to) return courier;

    final action = to == CourierRegistryStatus.active
        ? PosAuthorizedAction.activateCourier
        : PosAuthorizedAction.deactivateCourier;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'courierId': courierId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final updated = courier.copyWith(status: to);
    await _repository.save(updated);

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '$courierId-status-${now.microsecondsSinceEpoch}',
      branchId: courier.primaryBranchId,
      actorStaffId: performedByStaffId,
      courierId: courierId,
      type: to == CourierRegistryStatus.active
          ? CourierAuditEventType.courierActivated
          : to == CourierRegistryStatus.archived
              ? CourierAuditEventType.courierArchived
              : CourierAuditEventType.courierSuspended,
      description: 'Courier registry status: ${courier.status.name} -> '
          '${to.name}',
      previousStateName: courier.status.name,
      newStateName: to.name,
      reason: reason,
      timestamp: now,
      correlationId: '$courierId-status-${now.microsecondsSinceEpoch}',
    ));

    return updated;
  }
}
