import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/admin_audit_entry_repository.dart';
import '../../data/admin_device_registration_repository.dart';
import '../../domain/audit/admin_audit_entry.dart';
import '../../domain/audit/admin_audit_event_type.dart';
import '../../domain/device/admin_device_registration.dart';
import '../../domain/device/device_type.dart';
import '../identity/admin_device_registration_id_generator.dart';

/// Registers a new [AdminDeviceRegistration] — manager+
/// (`PosAuthorizedAction.manageDeviceRegistry`). Only valid for device
/// types with no other backing aggregate
/// ([DeviceType.posTerminal]/[DeviceType.printer]/
/// [DeviceType.paymentTerminal]) — [DeviceType.kitchenDisplay]/
/// [DeviceType.courierDevice] devices are registered through their own
/// bounded context (KDS pairing / courier device sign-in), never here.
class RegisterDevice {
  const RegisterDevice({
    required PosAuthorizationPolicy authorizationPolicy,
    required AdminDeviceRegistrationIdGenerator idGenerator,
    required AdminDeviceRegistrationRepository repository,
    required AdminAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final AdminDeviceRegistrationIdGenerator _idGenerator;
  final AdminDeviceRegistrationRepository _repository;
  final AdminAuditEntryRepository _auditRepository;

  static const _allowedTypes = {
    DeviceType.posTerminal,
    DeviceType.printer,
    DeviceType.paymentTerminal,
  };

  Future<AdminDeviceRegistration> call({
    required DeviceType type,
    required String branchId,
    required String label,
    String? softwareVersion,
    String? configurationRef,
    required String performedByStaffId,
    required DateTime registeredAt,
  }) async {
    if (!_allowedTypes.contains(type)) {
      throw AdminDeviceRegistrationTypeNotAllowedViolation(
        typeName: type.name,
      );
    }

    const action = PosAuthorizedAction.manageDeviceRegistry;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final registration = AdminDeviceRegistration(
      id: _idGenerator.nextAdminDeviceRegistrationId(),
      type: type,
      branchId: branchId,
      label: label,
      softwareVersion: softwareVersion,
      registeredByStaffId: performedByStaffId,
      configurationRef: configurationRef,
      registeredAt: registeredAt,
      revision: 1,
    );
    await _repository.save(registration);

    await _auditRepository.appendEvent(AdminAuditEntry(
      id: '${registration.id}-audit-registered',
      branchId: branchId,
      actorId: performedByStaffId,
      type: AdminAuditEventType.deviceRegistered,
      description: 'Device registered: "$label" (${type.name})',
      targetEntityId: registration.id,
      timestamp: registeredAt,
    ));

    return registration;
  }
}
