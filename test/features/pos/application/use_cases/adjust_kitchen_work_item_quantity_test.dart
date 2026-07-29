import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/adjust_kitchen_work_item_quantity.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';
import '../../test_support/kds_test_fixtures.dart';

void main() {
  group('AdjustKitchenWorkItemQuantity', () {
    test('increases quantity, preserving the original in the audit trail',
        () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      final item = buildTestKitchenWorkItem(quantity: 2);
      await projectionRepository.save(item);
      final auditRepository = InMemoryKitchenAuditEntryRepository();

      final useCase = AdjustKitchenWorkItemQuantity(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        projectionRepository: projectionRepository,
        auditRepository: auditRepository,
        recordKitchenEvent: buildTestRecordKitchenEvent(),
      );

      final updated = await useCase(
        workItemId: item.id,
        expectedRevision: item.revision,
        newQuantity: 5,
        reason: 'Müşteri ek sipariş verdi',
        performedByStaffId: 'staff-1',
      );

      expect(updated.quantity, 5);
      final entries = await auditRepository.findByOrderId('order-1');
      expect(entries.single.previousStateName, '2');
      expect(entries.single.newStateName, '5');
      expect(entries.single.reason, 'Müşteri ek sipariş verdi');
    });

    test('rejects reducing quantity below what is already ready', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      final item = buildTestKitchenWorkItem(quantity: 3, readyQuantity: 2);
      await projectionRepository.save(item);

      final useCase = AdjustKitchenWorkItemQuantity(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        projectionRepository: projectionRepository,
        auditRepository: InMemoryKitchenAuditEntryRepository(),
        recordKitchenEvent: buildTestRecordKitchenEvent(),
      );

      expect(
        () => useCase(
          workItemId: item.id,
          expectedRevision: item.revision,
          newQuantity: 1,
          reason: 'x',
          performedByStaffId: 'staff-1',
        ),
        throwsA(isA<InvalidKitchenLineTransitionViolation>()),
      );
    });
  });
}
