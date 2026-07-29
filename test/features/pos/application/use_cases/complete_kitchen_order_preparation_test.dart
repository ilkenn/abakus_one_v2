import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_channel.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/complete_kitchen_order_preparation.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';
import '../../test_support/kds_test_fixtures.dart';

void main() {
  group('CompleteKitchenOrderPreparation', () {
    test('throws when the order is not yet fully ready', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      await projectionRepository
          .save(buildTestKitchenWorkItem(status: KitchenLineStatus.preparing));

      final useCase = CompleteKitchenOrderPreparation(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        projectionRepository: projectionRepository,
        auditRepository: InMemoryKitchenAuditEntryRepository(),
        recordKitchenEvent: buildTestRecordKitchenEvent(),
      );

      expect(
        () => useCase(
          orderId: OrderId('order-1'),
          kitchenTicketId: 'ticket-1',
          branchId: 'branch-1',
          channel: OrderChannel.delivery,
          performedByStaffId: 'staff-1',
        ),
        throwsA(isA<KitchenOrderNotFullyReadyViolation>()),
      );
    });

    test(
        'advances package preparation for a delivery order once fully '
        'ready', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      await projectionRepository
          .save(buildTestKitchenWorkItem(status: KitchenLineStatus.ready));

      var advanceCalled = false;
      final useCase = CompleteKitchenOrderPreparation(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        projectionRepository: projectionRepository,
        auditRepository: InMemoryKitchenAuditEntryRepository(),
        recordKitchenEvent: buildTestRecordKitchenEvent(),
        advanceToReadyForPacking: ({
          required orderId,
          required performedByStaffId,
          required at,
        }) async {
          advanceCalled = true;
        },
      );

      await useCase(
        orderId: OrderId('order-1'),
        kitchenTicketId: 'ticket-1',
        branchId: 'branch-1',
        channel: OrderChannel.delivery,
        performedByStaffId: 'staff-1',
      );

      expect(advanceCalled, isTrue);
    });

    test('never touches package preparation for a dine-in order', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      await projectionRepository
          .save(buildTestKitchenWorkItem(status: KitchenLineStatus.ready));

      var advanceCalled = false;
      final useCase = CompleteKitchenOrderPreparation(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        projectionRepository: projectionRepository,
        auditRepository: InMemoryKitchenAuditEntryRepository(),
        recordKitchenEvent: buildTestRecordKitchenEvent(),
        advanceToReadyForPacking: ({
          required orderId,
          required performedByStaffId,
          required at,
        }) async {
          advanceCalled = true;
        },
      );

      await useCase(
        orderId: OrderId('order-1'),
        kitchenTicketId: 'ticket-1',
        branchId: 'branch-1',
        channel: OrderChannel.dineInStaff,
        performedByStaffId: 'staff-1',
      );

      expect(advanceCalled, isFalse);
    });
  });
}
