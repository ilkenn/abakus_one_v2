import 'device_type.dart';

/// One row of the unified Device Registry read-model — Phase 6L
/// (`docs/decisions.md` ADR-023). A normalized projection combining
/// `KitchenDisplayDevice`/`CourierDevice` (owned by their own bounded
/// contexts, read-only here) with `AdminDeviceRegistration` (the
/// admin-owned record for device types with no other backing
/// aggregate). See `BuildDeviceRegistryProjection`'s doc comment.
///
/// [softwareVersion], [registeredByStaffId], [configurationRef], and
/// [lastConnectionAt] are honestly `null` for [DeviceType.kitchenDisplay]
/// /[DeviceType.courierDevice] rows — neither `KitchenDisplayDevice` nor
/// `CourierDevice` tracks any of these fields today. Only rows sourced
/// from `AdminDeviceRegistration` populate them.
class DeviceRegistryEntry {
  const DeviceRegistryEntry({
    required this.id,
    required this.type,
    required this.branchId,
    required this.label,
    required this.isActive,
    this.isArchived = false,
    required this.registeredAt,
    this.softwareVersion,
    this.registeredByStaffId,
    this.configurationRef,
    this.lastConnectionAt,
  });

  /// The id of the underlying source record (`KitchenDisplayDevice.id`,
  /// `CourierDevice.id`, or `AdminDeviceRegistration.id`) — never a
  /// separately generated registry-row id, so a registry action can be
  /// routed straight back to its source.
  final String id;

  final DeviceType type;
  final String branchId;
  final String label;
  final bool isActive;

  /// Always `false` for [DeviceType.kitchenDisplay]/
  /// [DeviceType.courierDevice] rows — neither source device type has an
  /// archived concept, only `isActive`. Only `AdminDeviceRegistration`-
  /// backed rows can be `true`.
  final bool isArchived;

  final DateTime registeredAt;

  final String? softwareVersion;
  final String? registeredByStaffId;

  /// Opaque reference to a device's configuration, never inline
  /// configuration content — mirrors `CustomerPhoto.photoRef`'s "opaque
  /// reference, not the real content" shape.
  final String? configurationRef;

  /// No real remote connectivity monitoring is wired to this registry —
  /// always `null` today. A future backend integration seam, not a
  /// fabricated "last seen" value.
  final DateTime? lastConnectionAt;
}
