import '../../../courier/data/courier_device_repository.dart';
import '../../../courier/data/courier_repository.dart';
import '../../../pos/data/kitchen_display_device_repository.dart';
import '../../data/admin_device_registration_repository.dart';
import '../../domain/device/admin_device_registration_status.dart';
import '../../domain/device/device_registry_entry.dart';
import '../../domain/device/device_type.dart';

/// Builds the unified Device Registry read-model — Phase 6L
/// (`docs/decisions.md` ADR-023). A **projection**, not a merged
/// write-side store: `KitchenDisplayDevice`/`CourierDevice` keep living
/// in their own bounded contexts exactly as before; only
/// `AdminDeviceRegistration` (device types with no other owning
/// aggregate) is actually written here.
///
/// `CourierDeviceRepository` has no branch-scoped query (`CourierDevice`
/// itself carries no `branchId`, only `courierId`) — branch scoping for
/// courier devices is derived by first resolving this branch's couriers
/// via `CourierRepository.findByBranchId`, then looking up each
/// courier's devices (the same N+1-by-branch pattern
/// `BuildAdminOverviewSnapshot`'s `activeCourierCount` already uses).
class BuildDeviceRegistryProjection {
  const BuildDeviceRegistryProjection({
    required KitchenDisplayDeviceRepository kitchenDisplayDeviceRepository,
    required CourierRepository courierRepository,
    required CourierDeviceRepository courierDeviceRepository,
    required AdminDeviceRegistrationRepository
        adminDeviceRegistrationRepository,
  })  : _kitchenDisplayDeviceRepository = kitchenDisplayDeviceRepository,
        _courierRepository = courierRepository,
        _courierDeviceRepository = courierDeviceRepository,
        _adminDeviceRegistrationRepository = adminDeviceRegistrationRepository;

  final KitchenDisplayDeviceRepository _kitchenDisplayDeviceRepository;
  final CourierRepository _courierRepository;
  final CourierDeviceRepository _courierDeviceRepository;
  final AdminDeviceRegistrationRepository _adminDeviceRegistrationRepository;

  Future<List<DeviceRegistryEntry>> call({required String branchId}) async {
    final entries = <DeviceRegistryEntry>[];

    final kdsDevices =
        await _kitchenDisplayDeviceRepository.findByBranchId(branchId);
    entries.addAll(kdsDevices.map((d) => DeviceRegistryEntry(
          id: d.id,
          type: DeviceType.kitchenDisplay,
          branchId: d.branchId,
          label: d.name,
          isActive: d.isActive,
          registeredAt: d.registeredAt,
        )));

    final couriers = await _courierRepository.findByBranchId(branchId);
    for (final courier in couriers) {
      final courierDevices =
          await _courierDeviceRepository.findByCourierId(courier.id);
      entries.addAll(courierDevices.map((d) => DeviceRegistryEntry(
            id: d.id,
            type: DeviceType.courierDevice,
            branchId: branchId,
            label: d.platformLabel.isEmpty
                ? 'Kurye cihazı (${courier.displayName})'
                : '${d.platformLabel} (${courier.displayName})',
            isActive: d.isActive,
            registeredAt: d.registeredAt,
          )));
    }

    final adminDevices =
        await _adminDeviceRegistrationRepository.findByBranchId(branchId);
    entries.addAll(adminDevices.map((d) => DeviceRegistryEntry(
          id: d.id,
          type: d.type,
          branchId: d.branchId,
          label: d.label,
          isActive: d.status == AdminDeviceRegistrationStatus.active,
          isArchived: d.status == AdminDeviceRegistrationStatus.archived,
          registeredAt: d.registeredAt,
          softwareVersion: d.softwareVersion,
          registeredByStaffId: d.registeredByStaffId,
          configurationRef: d.configurationRef,
        )));

    entries.sort((a, b) => b.registeredAt.compareTo(a.registeredAt));
    return entries;
  }
}
