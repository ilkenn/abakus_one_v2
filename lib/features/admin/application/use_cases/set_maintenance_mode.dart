import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/maintenance_mode_state_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/system/maintenance_mode_state.dart';

/// Activates/deactivates the global [MaintenanceModeState] — admin-only
/// (`PosAuthorizedAction.manageMaintenanceMode`). "Maintenance mode
/// foundation" — see [MaintenanceModeState]'s own doc comment for what
/// this does and does not do.
class SetMaintenanceMode {
  const SetMaintenanceMode({
    required PosAuthorizationPolicy authorizationPolicy,
    required MaintenanceModeStateRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final MaintenanceModeStateRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<MaintenanceModeState> call({
    required bool isActive,
    String? reason,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageMaintenanceMode;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.find();
    final updated =
        (existing ?? const MaintenanceModeState(revision: 0)).copyWith(
      isActive: isActive,
      reason: reason,
      clearReason: !isActive && reason == null,
      changedByStaffId: performedByStaffId,
      changedAt: performedAt,
      revision: (existing?.revision ?? 0) + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: 'maintenance-mode-audit-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: AdminAuditEventType.maintenanceModeChanged,
      description: 'Maintenance mode ${isActive ? 'activated' : 'deactivated'}'
          '${reason != null ? ' ($reason)' : ''}',
      targetEntityId: 'maintenance-mode',
      previousStateName: (existing?.isActive ?? false).toString(),
      newStateName: isActive.toString(),
      timestamp: performedAt,
    ));

    return updated;
  }
}
