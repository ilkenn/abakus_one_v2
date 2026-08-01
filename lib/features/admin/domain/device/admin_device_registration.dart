import 'admin_device_registration_status.dart';
import 'device_type.dart';

/// An admin-registered device — the only registry record that exists at
/// all for [DeviceType.posTerminal]/[DeviceType.printer]/
/// [DeviceType.paymentTerminal], which have no other backing domain
/// aggregate (Phase 6L, `docs/decisions.md` ADR-023). Mutable registry
/// entity, mirroring `Branch`/`StaffMember`: current shape is what
/// matters, not a revision history of it — `archived` is terminal (see
/// `AdminDeviceRegistrationStatus`).
///
/// Not used for [DeviceType.kitchenDisplay]/[DeviceType.courierDevice] —
/// those already have a real owning aggregate
/// (`KitchenDisplayDevice`/`CourierDevice`); registering a second record
/// here for them would be exactly the "merge device domain aggregates
/// destructively" the brief warns against.
class AdminDeviceRegistration {
  const AdminDeviceRegistration({
    required this.id,
    required this.type,
    required this.branchId,
    required this.label,
    this.status = AdminDeviceRegistrationStatus.active,
    this.softwareVersion,
    required this.registeredByStaffId,
    this.configurationRef,
    required this.registeredAt,
    required this.revision,
  });

  final String id;
  final DeviceType type;
  final String branchId;
  final String label;
  final AdminDeviceRegistrationStatus status;
  final String? softwareVersion;
  final String registeredByStaffId;
  final String? configurationRef;
  final DateTime registeredAt;
  final int revision;

  AdminDeviceRegistration copyWith({
    String? label,
    AdminDeviceRegistrationStatus? status,
    String? softwareVersion,
    bool clearSoftwareVersion = false,
    String? configurationRef,
    bool clearConfigurationRef = false,
    required int revision,
  }) {
    return AdminDeviceRegistration(
      id: id,
      type: type,
      branchId: branchId,
      label: label ?? this.label,
      status: status ?? this.status,
      softwareVersion: clearSoftwareVersion
          ? null
          : (softwareVersion ?? this.softwareVersion),
      registeredByStaffId: registeredByStaffId,
      configurationRef: clearConfigurationRef
          ? null
          : (configurationRef ?? this.configurationRef),
      registeredAt: registeredAt,
      revision: revision,
    );
  }
}
