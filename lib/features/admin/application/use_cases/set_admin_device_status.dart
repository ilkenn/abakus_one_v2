import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/admin_device_registration_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/device/admin_device_registration.dart';
import '../../domain/device/admin_device_registration_status.dart';

/// Activates, deactivates ("revokes"), or archives an
/// [AdminDeviceRegistration] — manager+
/// (`PosAuthorizedAction.manageDeviceRegistry`). `active <-> inactive`
/// is reversible ("revoke" = set `inactive`, reinstatable);
/// `-> archived` is terminal, mirroring `SetBranchStatus`/
/// `SetStaffMemberStatus`.
class SetAdminDeviceStatus {
  const SetAdminDeviceStatus({
    required PosAuthorizationPolicy authorizationPolicy,
    required AdminDeviceRegistrationRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final AdminDeviceRegistrationRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  Future<AdminDeviceRegistration> call({
    required String deviceId,
    required AdminDeviceRegistrationStatus newStatus,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageDeviceRegistry;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.findById(deviceId);
    if (existing == null) {
      throw UnknownAdminEntityViolation(
        entityName: 'AdminDeviceRegistration',
        id: deviceId,
      );
    }

    // A second check, now that the device's branch is known — "cross-
    // branch access must require explicit authorization" (Phase 6P).
    // The base action/role check above already passed identically; this
    // call can only newly deny on the branch-scope check.
    final branchScopedAuthResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kBranchIdAuthorizationContextKey: existing.branchId},
    );
    if (!branchScopedAuthResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    if (existing.status == AdminDeviceRegistrationStatus.archived) {
      throw AdminDeviceRegistrationArchivedViolation(deviceId: deviceId);
    }

    final updated = existing.copyWith(
      status: newStatus,
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '$deviceId-audit-status-${performedAt.microsecondsSinceEpoch}',
      branchId: existing.branchId,
      actorId: performedByStaffId,
      type: AdminAuditEventType.deviceStatusChanged,
      description: 'Device status changed to "${newStatus.name}"',
      targetEntityId: deviceId,
      previousStateName: existing.status.name,
      newStateName: newStatus.name,
      timestamp: performedAt,
    ));

    return updated;
  }
}
