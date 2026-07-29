import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/cancel_kitchen_work_items_for_order.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/transition_kitchen_work_item.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/fake_pos_authorization_policy.dart';
import '../../test_support/kds_test_fixtures.dart';

void main() {
  group('CancelKitchenWorkItemsForOrder', () {
    test(
        'cancels every still-active line for the order (full order '
        'cancellation)', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      await projectionRepository.save(buildTestKitchenWorkItem(
        workItemId: 'w1',
        kitchenTicketLineId: 'ticket-1-line-0',
      ));
      await projectionRepository.save(buildTestKitchenWorkItem(
        workItemId: 'w2',
        kitchenTicketLineId: 'ticket-1-line-1',
        status: KitchenLineStatus.preparing,
        preparingStartedAt: DateTime(2026, 1, 1, 12),
      ));

      final useCase = CancelKitchenWorkItemsForOrder(
        projectionRepository: projectionRepository,
        transitionKitchenWorkItem: TransitionKitchenWorkItem(
          clock: FakeClock(DateTime(2026, 1, 1, 12, 30)),
          authorizationPolicy: FakePosAuthorizationPolicy(
              const AuthorizationResult(granted: true)),
          projectionRepository: projectionRepository,
          auditRepository: InMemoryKitchenAuditEntryRepository(),
          recordKitchenEvent: buildTestRecordKitchenEvent(),
        ),
      );

      final cancelled = await useCase(
        orderId: OrderId('order-1'),
        reason: 'Müşteri iptal etti',
        performedByStaffId: 'staff-1',
      );

      expect(cancelled, hasLength(2));
      expect(cancelled.every((i) => i.status == KitchenLineStatus.cancelled),
          isTrue);
    });

    test('skips already-terminal items rather than failing outright', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      await projectionRepository.save(buildTestKitchenWorkItem(
        workItemId: 'w1',
        status: KitchenLineStatus.ready,
      ));

      final useCase = CancelKitchenWorkItemsForOrder(
        projectionRepository: projectionRepository,
        transitionKitchenWorkItem: TransitionKitchenWorkItem(
          clock: FakeClock(DateTime(2026, 1, 1, 12)),
          authorizationPolicy: FakePosAuthorizationPolicy(
              const AuthorizationResult(granted: true)),
          projectionRepository: projectionRepository,
          auditRepository: InMemoryKitchenAuditEntryRepository(),
          recordKitchenEvent: buildTestRecordKitchenEvent(),
        ),
      );

      final cancelled = await useCase(
        orderId: OrderId('order-1'),
        reason: 'x',
        performedByStaffId: 'staff-1',
      );

      expect(cancelled, isEmpty);
    });
  });
}
