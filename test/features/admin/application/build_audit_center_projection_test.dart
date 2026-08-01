import 'package:abakus_one_v2/features/admin/application/use_cases/build_audit_center_projection.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/audit/admin_audit_entry.dart';
import 'package:abakus_one_v2/features/admin/domain/audit/admin_audit_event_type.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/audit/courier_audit_event_type.dart';
import 'package:abakus_one_v2/features/courier/domain/audit/courier_operational_audit_entry.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_audit_entry.dart';
import 'package:abakus_one_v2/features/restaurant/data/restaurant_operations_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/restaurant/domain/audit/restaurant_operations_audit_entry.dart';
import 'package:abakus_one_v2/features/restaurant/domain/audit/restaurant_operations_audit_event_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryCourierOperationalAuditEntryRepository courierRepository;
  late InMemoryKitchenAuditEntryRepository kitchenRepository;
  late InMemoryRestaurantOperationsAuditEntryRepository restaurantOpsRepository;
  late InMemoryAdminAuditEntryRepository adminRepository;
  late BuildAuditCenterProjection useCase;

  setUp(() async {
    courierRepository = InMemoryCourierOperationalAuditEntryRepository();
    kitchenRepository = InMemoryKitchenAuditEntryRepository();
    restaurantOpsRepository =
        InMemoryRestaurantOperationsAuditEntryRepository();
    adminRepository = InMemoryAdminAuditEntryRepository();
    useCase = BuildAuditCenterProjection(
      courierAuditRepository: courierRepository,
      kitchenAuditRepository: kitchenRepository,
      restaurantOperationsAuditRepository: restaurantOpsRepository,
      adminAuditRepository: adminRepository,
    );

    await courierRepository.appendEvent(CourierOperationalAuditEntry(
      id: 'courier-audit-1',
      branchId: 'branch-1',
      actorStaffId: 'courier-1',
      actorRole: 'courier',
      deliveryId: 'delivery-1',
      type: CourierAuditEventType.assignmentAccepted,
      description: 'Teslimat kabul edildi',
      timestamp: DateTime(2026, 1, 1, 10),
      correlationId: 'corr-1',
    ));
    await kitchenRepository.appendEvent(KitchenAuditEntry(
      id: 'kitchen-audit-1',
      branchId: 'branch-1',
      orderId: 'order-1',
      type: KitchenAuditEventType.markedReady,
      description: 'Sipariş hazır',
      actorStaffId: 'staff-1',
      timestamp: DateTime(2026, 1, 1, 11),
      correlationId: 'corr-2',
    ));
    await restaurantOpsRepository.appendEvent(RestaurantOperationsAuditEntry(
      id: 'restaurant-ops-audit-1',
      branchId: 'branch-1',
      type: RestaurantOperationsAuditEventType.channelOperationalStateChanged,
      description: 'Kanal politikası değişti',
      actorStaffId: 'manager-1',
      timestamp: DateTime(2026, 1, 1, 12),
    ));
    await adminRepository.appendEvent(AdminAuditEntry(
      id: 'admin-audit-1',
      branchId: 'branch-1',
      actorId: 'admin-1',
      actorRole: 'admin',
      type: AdminAuditEventType.staffRoleGranted,
      description: 'Rol atandı',
      targetEntityId: 'staff-2',
      timestamp: DateTime(2026, 1, 1, 13),
    ));
    // A different branch — must never leak into 'branch-1' queries.
    await adminRepository.appendEvent(AdminAuditEntry(
      id: 'admin-audit-2',
      branchId: 'branch-9',
      actorId: 'admin-1',
      type: AdminAuditEventType.staffRoleGranted,
      description: 'Başka şube kaydı',
      targetEntityId: 'staff-3',
      timestamp: DateTime(2026, 1, 1, 14),
    ));
  });

  test('merges all 4 branch-scoped audit sources, newest first', () async {
    final entries = await useCase(branchId: 'branch-1');

    expect(entries.map((e) => e.id).toList(), [
      'admin-audit-1',
      'restaurant-ops-audit-1',
      'kitchen-audit-1',
      'courier-audit-1',
    ]);
    expect(entries.map((e) => e.domain).toSet(), {
      'admin',
      'restaurant-operations',
      'kitchen',
      'courier',
    });
  });

  test('never leaks another branch\'s entries', () async {
    final entries = await useCase(branchId: 'branch-1');

    expect(entries.any((e) => e.id == 'admin-audit-2'), isFalse);
  });

  test('filters by domain', () async {
    final entries = await useCase(branchId: 'branch-1', domain: 'courier');

    expect(entries, hasLength(1));
    expect(entries.single.id, 'courier-audit-1');
  });

  test('filters by actorId', () async {
    final entries = await useCase(branchId: 'branch-1', actorId: 'manager-1');

    expect(entries, hasLength(1));
    expect(entries.single.id, 'restaurant-ops-audit-1');
  });

  test('filters by date range', () async {
    final entries = await useCase(
      branchId: 'branch-1',
      from: DateTime(2026, 1, 1, 11, 30),
      to: DateTime(2026, 1, 1, 12, 30),
    );

    expect(entries, hasLength(1));
    expect(entries.single.id, 'restaurant-ops-audit-1');
  });

  test('applies the limit after sorting', () async {
    final entries = await useCase(branchId: 'branch-1', limit: 2);

    expect(entries.map((e) => e.id).toList(),
        ['admin-audit-1', 'restaurant-ops-audit-1']);
  });
}
