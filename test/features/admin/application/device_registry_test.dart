import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/application/identity/admin_device_registration_id_generator.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/build_device_registry_projection.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/register_device.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/set_admin_device_status.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/set_source_device_active.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/admin_device_registration_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/device/admin_device_registration.dart';
import 'package:abakus_one_v2/features/admin/domain/device/admin_device_registration_status.dart';
import 'package:abakus_one_v2/features/admin/domain/device/device_type.dart';
import 'package:abakus_one_v2/features/courier/data/courier_device_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/device/courier_device.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier_vehicle_type.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_display_device_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_display_device.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  group('RegisterDevice', () {
    test('registers a POS terminal', () async {
      final repository = InMemoryAdminDeviceRegistrationRepository();
      final useCase = RegisterDevice(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialAdminDeviceRegistrationIdGenerator(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final device = await useCase(
        type: DeviceType.posTerminal,
        branchId: 'branch-1',
        label: 'Kasa 1',
        performedByStaffId: 'manager-1',
        registeredAt: DateTime(2026, 1, 1),
      );

      expect(device.type, DeviceType.posTerminal);
      expect(await repository.findById(device.id), isNotNull);
    });

    test(
        'rejects kitchenDisplay/courierDevice — those have their own '
        'owning aggregate', () async {
      final useCase = RegisterDevice(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialAdminDeviceRegistrationIdGenerator(),
        repository: InMemoryAdminDeviceRegistrationRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          type: DeviceType.kitchenDisplay,
          branchId: 'branch-1',
          label: 'KDS 1',
          performedByStaffId: 'manager-1',
          registeredAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AdminDeviceRegistrationTypeNotAllowedViolation>()),
      );
    });

    test('an unauthorized actor cannot register a device', () async {
      final useCase = RegisterDevice(
        authorizationPolicy: const DenyAllAdminPolicy(),
        idGenerator: SequentialAdminDeviceRegistrationIdGenerator(),
        repository: InMemoryAdminDeviceRegistrationRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          type: DeviceType.printer,
          branchId: 'branch-1',
          label: 'Mutfak Yazıcısı',
          performedByStaffId: 'staff-1',
          registeredAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('SetAdminDeviceStatus', () {
    test('archived is terminal', () async {
      final repository = InMemoryAdminDeviceRegistrationRepository();
      await repository.save(AdminDeviceRegistration(
        id: 'device-1',
        type: DeviceType.printer,
        branchId: 'branch-1',
        label: 'Yazıcı',
        status: AdminDeviceRegistrationStatus.archived,
        registeredByStaffId: 'manager-1',
        registeredAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final useCase = SetAdminDeviceStatus(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          deviceId: 'device-1',
          newStatus: AdminDeviceRegistrationStatus.active,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 2),
        ),
        throwsA(isA<AdminDeviceRegistrationArchivedViolation>()),
      );
    });

    test('deactivates ("revokes") an active device', () async {
      final repository = InMemoryAdminDeviceRegistrationRepository();
      await repository.save(AdminDeviceRegistration(
        id: 'device-1',
        type: DeviceType.posTerminal,
        branchId: 'branch-1',
        label: 'Kasa 1',
        registeredByStaffId: 'manager-1',
        registeredAt: DateTime(2026, 1, 1),
        revision: 1,
      ));
      final useCase = SetAdminDeviceStatus(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final updated = await useCase(
        deviceId: 'device-1',
        newStatus: AdminDeviceRegistrationStatus.inactive,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(updated.status, AdminDeviceRegistrationStatus.inactive);
    });
  });

  group('SetSourceDeviceActive', () {
    test('toggles a KitchenDisplayDevice', () async {
      final kdsRepository = InMemoryKitchenDisplayDeviceRepository();
      await kdsRepository.save(KitchenDisplayDevice(
        id: 'kds-1',
        branchId: 'branch-1',
        name: 'Ekran 1',
        registeredAt: DateTime(2026, 1, 1),
      ));
      final useCase = SetSourceDeviceActive(
        authorizationPolicy: const AllowAllAdminPolicy(),
        kitchenDisplayDeviceRepository: kdsRepository,
        courierDeviceRepository: InMemoryCourierDeviceRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      await useCase(
        type: DeviceType.kitchenDisplay,
        deviceId: 'kds-1',
        isActive: false,
        branchId: 'branch-1',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      final updated = await kdsRepository.findById('kds-1');
      expect(updated!.isActive, isFalse);
    });

    test('toggles a CourierDevice', () async {
      final courierDeviceRepository = InMemoryCourierDeviceRepository();
      await courierDeviceRepository.save(CourierDevice(
        id: 'courier-device-1',
        courierId: 'courier-1',
        registeredAt: DateTime(2026, 1, 1),
      ));
      final useCase = SetSourceDeviceActive(
        authorizationPolicy: const AllowAllAdminPolicy(),
        kitchenDisplayDeviceRepository:
            InMemoryKitchenDisplayDeviceRepository(),
        courierDeviceRepository: courierDeviceRepository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      await useCase(
        type: DeviceType.courierDevice,
        deviceId: 'courier-device-1',
        isActive: false,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      final updated =
          await courierDeviceRepository.findById('courier-device-1');
      expect(updated!.isActive, isFalse);
    });

    test('rejects a posTerminal type — no source repository to toggle',
        () async {
      final useCase = SetSourceDeviceActive(
        authorizationPolicy: const AllowAllAdminPolicy(),
        kitchenDisplayDeviceRepository:
            InMemoryKitchenDisplayDeviceRepository(),
        courierDeviceRepository: InMemoryCourierDeviceRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          type: DeviceType.posTerminal,
          deviceId: 'device-1',
          isActive: false,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 2),
        ),
        throwsA(isA<NoSourceDeviceRepositoryViolation>()),
      );
    });
  });

  group('BuildDeviceRegistryProjection', () {
    test('merges KDS, courier, and admin-registered devices for a branch',
        () async {
      final kdsRepository = InMemoryKitchenDisplayDeviceRepository();
      await kdsRepository.save(KitchenDisplayDevice(
        id: 'kds-1',
        branchId: 'branch-1',
        name: 'Ekran 1',
        registeredAt: DateTime(2026, 1, 1),
      ));

      final courierRepository = InMemoryCourierRepository();
      await courierRepository.save(Courier(
        id: 'courier-1',
        primaryBranchId: 'branch-1',
        displayName: 'Kurye Bir',
        phoneNumber: '5551234567',
        vehicleType: CourierVehicleType.motorcycle,
        capacity: 3,
        registeredAt: DateTime(2026, 1, 1),
      ));
      final courierDeviceRepository = InMemoryCourierDeviceRepository();
      await courierDeviceRepository.save(CourierDevice(
        id: 'courier-device-1',
        courierId: 'courier-1',
        platformLabel: 'Android',
        registeredAt: DateTime(2026, 1, 2),
      ));

      final adminDeviceRepository = InMemoryAdminDeviceRegistrationRepository();
      await adminDeviceRepository.save(AdminDeviceRegistration(
        id: 'pos-1',
        type: DeviceType.posTerminal,
        branchId: 'branch-1',
        label: 'Kasa 1',
        registeredByStaffId: 'manager-1',
        registeredAt: DateTime(2026, 1, 3),
        revision: 1,
      ));

      final useCase = BuildDeviceRegistryProjection(
        kitchenDisplayDeviceRepository: kdsRepository,
        courierRepository: courierRepository,
        courierDeviceRepository: courierDeviceRepository,
        adminDeviceRegistrationRepository: adminDeviceRepository,
      );

      final entries = await useCase(branchId: 'branch-1');

      expect(entries.map((e) => e.id).toSet(),
          {'kds-1', 'courier-device-1', 'pos-1'});
      expect(entries.first.id, 'pos-1'); // newest registeredAt first
    });
  });
}
