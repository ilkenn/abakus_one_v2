import 'package:abakus_one_v2/features/pos/application/identity/kitchen_work_item_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/enqueue_kitchen_work_items.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_projection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_routing_rule_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_line_status.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_routing_rule.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_station.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';
import '../../test_support/kds_test_fixtures.dart';

void main() {
  group('EnqueueKitchenWorkItems', () {
    test('creates one queued work item per ticket line', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      final useCase = EnqueueKitchenWorkItems(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialKitchenWorkItemIdGenerator(),
        projectionRepository: projectionRepository,
        routingRuleRepository: InMemoryKitchenRoutingRuleRepository(),
        recordKitchenEvent: buildTestRecordKitchenEvent(),
      );
      final ticket = buildTestKitchenTicket(lineCount: 2);

      final created = await useCase(ticket: ticket);

      expect(created, hasLength(2));
      expect(
          created.every((i) => i.status == KitchenLineStatus.queued), isTrue);
      final stored =
          await projectionRepository.findByBranch(branchId: 'branch-1');
      expect(stored, hasLength(2));
    });

    test(
        'is idempotent per (ticket, line) — re-enqueueing the same ticket '
        'creates no duplicate work', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      final useCase = EnqueueKitchenWorkItems(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialKitchenWorkItemIdGenerator(),
        projectionRepository: projectionRepository,
        routingRuleRepository: InMemoryKitchenRoutingRuleRepository(),
        recordKitchenEvent: buildTestRecordKitchenEvent(),
      );
      final ticket = buildTestKitchenTicket(lineCount: 2);

      final firstBatch = await useCase(ticket: ticket);
      final secondBatch = await useCase(ticket: ticket);

      expect(firstBatch, hasLength(2));
      expect(secondBatch, isEmpty);
      final stored =
          await projectionRepository.findByBranch(branchId: 'branch-1');
      expect(stored, hasLength(2));
    });

    test('routes a line via a matching branch rule', () async {
      final projectionRepository = InMemoryKitchenProjectionRepository();
      final routingRuleRepository = InMemoryKitchenRoutingRuleRepository();
      await routingRuleRepository.save(const KitchenRoutingRule(
        id: 'r1',
        branchId: 'branch-1',
        priority: 1,
        criteria: KitchenRoutingCriteria(productId: 'product-1'),
        targetStation: KitchenStation.hot,
      ));
      final useCase = EnqueueKitchenWorkItems(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialKitchenWorkItemIdGenerator(),
        projectionRepository: projectionRepository,
        routingRuleRepository: routingRuleRepository,
        recordKitchenEvent: buildTestRecordKitchenEvent(),
      );
      final ticket = buildTestKitchenTicket(lineCount: 1);

      final created = await useCase(
        ticket: ticket,
        routingHintsByLineId: {
          ticket.lines.single.id: (
            productId: 'product-1',
            categoryId: null,
            modifierCodes: <String>{},
            channelName: null,
          ),
        },
      );

      expect(created.single.station, KitchenStation.hot);
    });
  });
}
