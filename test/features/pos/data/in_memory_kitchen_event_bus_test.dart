import 'package:abakus_one_v2/features/pos/data/in_memory_kitchen_event_bus.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_event.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_event_type.dart';
import 'package:flutter_test/flutter_test.dart';

KitchenEvent _event(String id, String branchId) {
  return KitchenEvent(
    id: id,
    branchId: branchId,
    type: KitchenEventType.workItemQueued,
    idempotencyKey: id,
    sequence: 0,
    occurredAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('InMemoryKitchenEventBus', () {
    test('delivers published events to a subscriber in publish order',
        () async {
      final bus = InMemoryKitchenEventBus();
      final received = <String>[];
      final subscription =
          bus.subscribe(branchId: 'branch-1').listen((e) => received.add(e.id));

      await bus.publish(_event('e1', 'branch-1'));
      await bus.publish(_event('e2', 'branch-1'));
      await Future<void>.delayed(Duration.zero);

      expect(received, ['e1', 'e2']);
      await subscription.cancel();
      await bus.closeAll();
    });

    test('a branch-1 subscriber never receives branch-2 events', () async {
      final bus = InMemoryKitchenEventBus();
      final received = <String>[];
      final subscription =
          bus.subscribe(branchId: 'branch-1').listen((e) => received.add(e.id));

      await bus.publish(_event('e1', 'branch-2'));
      await Future<void>.delayed(Duration.zero);

      expect(received, isEmpty);
      await subscription.cancel();
      await bus.closeAll();
    });
  });
}
