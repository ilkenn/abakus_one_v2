import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_operation_timeline.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/audit/courier_audit_event_type.dart';
import 'package:abakus_one_v2/features/courier/domain/audit/courier_operational_audit_entry.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/courier_test_fixtures.dart';

CourierOperationalAuditEntry _entry({
  required String id,
  required DateTime timestamp,
  required CourierAuditEventType type,
  String? courierId,
  String description = 'test entry',
  String branchId = 'branch-1',
}) {
  return CourierOperationalAuditEntry(
    id: id,
    branchId: branchId,
    actorStaffId: 'staff-1',
    courierId: courierId,
    type: type,
    description: description,
    timestamp: timestamp,
    correlationId: 'corr-$id',
  );
}

void main() {
  group('BuildCourierOperationTimeline', () {
    test('orders entries most-recent-first and resolves courier names',
        () async {
      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      final courierRepository = InMemoryCourierRepository();
      await courierRepository.save(buildTestCourier(
        id: 'courier-1',
        displayName: 'Ahmet',
      ));

      await auditRepository.appendEvent(_entry(
        id: 'entry-1',
        timestamp: DateTime(2026, 1, 1, 12, 1),
        type: CourierAuditEventType.shiftStarted,
        courierId: 'courier-1',
        description: 'Ahmet vardiyaya başladı',
      ));
      await auditRepository.appendEvent(_entry(
        id: 'entry-2',
        timestamp: DateTime(2026, 1, 1, 12, 27),
        type: CourierAuditEventType.emergencyMessageSent,
        description: "Yönetici Mehmet'e acil mesaj gönderdi",
      ));

      final useCase = BuildCourierOperationTimeline(
        auditRepository: auditRepository,
        courierRepository: courierRepository,
      );

      final timeline = await useCase(branchId: 'branch-1');

      expect(timeline, hasLength(2));
      expect(timeline.first.type, CourierAuditEventType.emergencyMessageSent);
      expect(timeline.last.type, CourierAuditEventType.shiftStarted);
      expect(timeline.last.courierDisplayName, 'Ahmet');
      expect(timeline.first.courierDisplayName, isNull);
    });

    test('only includes entries for the requested branch', () async {
      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      await auditRepository.appendEvent(_entry(
        id: 'entry-1',
        timestamp: DateTime(2026, 1, 1, 12),
        type: CourierAuditEventType.shiftStarted,
        branchId: 'branch-1',
      ));
      await auditRepository.appendEvent(_entry(
        id: 'entry-2',
        timestamp: DateTime(2026, 1, 1, 12),
        type: CourierAuditEventType.shiftStarted,
        branchId: 'branch-2',
      ));

      final useCase = BuildCourierOperationTimeline(
        auditRepository: auditRepository,
        courierRepository: InMemoryCourierRepository(),
      );

      final timeline = await useCase(branchId: 'branch-1');

      expect(timeline, hasLength(1));
    });

    test('a courier id with no matching courier record yields a null name',
        () async {
      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      await auditRepository.appendEvent(_entry(
        id: 'entry-1',
        timestamp: DateTime(2026, 1, 1, 12),
        type: CourierAuditEventType.shiftStarted,
        courierId: 'unknown-courier',
      ));

      final useCase = BuildCourierOperationTimeline(
        auditRepository: auditRepository,
        courierRepository: InMemoryCourierRepository(),
      );

      final timeline = await useCase(branchId: 'branch-1');

      expect(timeline.single.courierId, 'unknown-courier');
      expect(timeline.single.courierDisplayName, isNull);
    });
  });
}
