import '../../../../core/errors/business_rule_violation.dart';
import '../../../courier/data/courier_device_repository.dart';
import '../../../pos/data/kitchen_display_device_repository.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/device/device_type.dart';

/// Toggles `isActive` on a source-owned device
/// ([DeviceType.kitchenDisplay]/[DeviceType.courierDevice]) — manager+
/// (`PosAuthorizedAction.manageDeviceRegistry`). Writes back through the
/// device's own owning repository (`KitchenDisplayDeviceRepository`/
/// `CourierDeviceRepository`) — the Admin Platform never holds a
/// competing copy of these devices, only toggles the one field their
/// own bounded context already exposes. "Do not merge device domain
/// aggregates destructively" (Phase 6L, `docs/decisions.md` ADR-023).
///
/// Neither source device type carries a revision counter or an
/// `archived` state — only [DeviceType.kitchenDisplay]/
/// [DeviceType.courierDevice]'s `isActive` toggle is available here;
/// "archive" is a concept `AdminDeviceRegistration`-backed device types
/// have, these do not.
class SetSourceDeviceActive {
  const SetSourceDeviceActive({
    required PosAuthorizationPolicy authorizationPolicy,
    required KitchenDisplayDeviceRepository kitchenDisplayDeviceRepository,
    required CourierDeviceRepository courierDeviceRepository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _kitchenDisplayDeviceRepository = kitchenDisplayDeviceRepository,
        _courierDeviceRepository = courierDeviceRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final KitchenDisplayDeviceRepository _kitchenDisplayDeviceRepository;
  final CourierDeviceRepository _courierDeviceRepository;
  final AdminAuditEntryRepository _auditRepository;

  Future<void> call({
    required DeviceType type,
    required String deviceId,
    required bool isActive,
    String? branchId,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageDeviceRegistry;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: branchId == null
          ? const {}
          : {kBranchIdAuthorizationContextKey: branchId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    switch (type) {
      case DeviceType.kitchenDisplay:
        final existing =
            await _kitchenDisplayDeviceRepository.findById(deviceId);
        if (existing == null) {
          throw UnknownAdminEntityViolation(
            entityName: 'KitchenDisplayDevice',
            id: deviceId,
          );
        }
        await _kitchenDisplayDeviceRepository
            .save(existing.copyWith(isActive: isActive));
      case DeviceType.courierDevice:
        final existing = await _courierDeviceRepository.findById(deviceId);
        if (existing == null) {
          throw UnknownAdminEntityViolation(
            entityName: 'CourierDevice',
            id: deviceId,
          );
        }
        await _courierDeviceRepository
            .save(existing.copyWith(isActive: isActive));
      case DeviceType.posTerminal:
      case DeviceType.printer:
      case DeviceType.paymentTerminal:
        throw NoSourceDeviceRepositoryViolation(typeName: type.name);
    }

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '$deviceId-audit-status-${performedAt.microsecondsSinceEpoch}',
      branchId: branchId,
      actorId: performedByStaffId,
      type: AdminAuditEventType.deviceStatusChanged,
      description:
          'Device "$deviceId" (${type.name}) active status set to $isActive',
      targetEntityId: deviceId,
      newStateName: isActive ? 'active' : 'inactive',
      timestamp: performedAt,
    ));
  }
}
