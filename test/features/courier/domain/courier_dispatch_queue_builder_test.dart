import 'package:abakus_one_v2/features/courier/domain/dispatch/courier_dispatch_queue_builder.dart';
import 'package:abakus_one_v2/features/courier/domain/dispatch/courier_dispatch_queue_event.dart';
import 'package:flutter_test/flutter_test.dart';

CourierDispatchQueueEvent _entered({
  required String id,
  required String courierId,
  required DateTime occurredAt,
}) {
  return CourierDispatchQueueEvent(
    id: id,
    branchId: 'branch-1',
    courierId: courierId,
    type: CourierDispatchQueueEventType.entered,
    occurredAt: occurredAt,
  );
}

CourierDispatchQueueEvent _left({
  required String id,
  required String courierId,
  required DateTime occurredAt,
  CourierDispatchQueueLeaveReason reason =
      CourierDispatchQueueLeaveReason.activeDelivery,
}) {
  return CourierDispatchQueueEvent(
    id: id,
    branchId: 'branch-1',
    courierId: courierId,
    type: CourierDispatchQueueEventType.left,
    leaveReason: reason,
    occurredAt: occurredAt,
  );
}

void main() {
  group('CourierDispatchQueueBuilder.build', () {
    test(
        'the brief\'s own worked example: three couriers arriving in '
        'order queue 1/2/3', () {
      final positions = CourierDispatchQueueBuilder.build([
        _entered(
            id: '1',
            courierId: 'ahmet',
            occurredAt: DateTime(2026, 1, 1, 9, 50)),
        _entered(
            id: '2',
            courierId: 'mehmet',
            occurredAt: DateTime(2026, 1, 1, 9, 55)),
        _entered(
            id: '3', courierId: 'ali', occurredAt: DateTime(2026, 1, 1, 9, 58)),
      ]);

      expect(positions.map((p) => p.courierId).toList(),
          ['ahmet', 'mehmet', 'ali']);
      expect(positions[0].position, 1);
      expect(positions[1].position, 2);
      expect(positions[2].position, 3);
    });

    test('a courier whose latest event is "left" is not in the queue', () {
      final positions = CourierDispatchQueueBuilder.build([
        _entered(
            id: '1',
            courierId: 'ahmet',
            occurredAt: DateTime(2026, 1, 1, 9, 50)),
        _left(
            id: '2',
            courierId: 'ahmet',
            occurredAt: DateTime(2026, 1, 1, 10, 0)),
      ]);
      expect(positions, isEmpty);
    });

    test(
        're-entering after leaving always goes to the back, never the '
        'original position', () {
      final positions = CourierDispatchQueueBuilder.build([
        _entered(
            id: '1',
            courierId: 'ahmet',
            occurredAt: DateTime(2026, 1, 1, 9, 50)),
        _entered(
            id: '2',
            courierId: 'mehmet',
            occurredAt: DateTime(2026, 1, 1, 9, 55)),
        // Ahmet takes a delivery and returns after Mehmet is already
        // waiting.
        _left(
            id: '3',
            courierId: 'ahmet',
            occurredAt: DateTime(2026, 1, 1, 10, 0)),
        _entered(
            id: '4',
            courierId: 'ahmet',
            occurredAt: DateTime(2026, 1, 1, 10, 30)),
      ]);

      expect(positions.map((p) => p.courierId).toList(), ['mehmet', 'ahmet']);
    });

    test(
        'only the latest event per courier matters, regardless of input '
        'order', () {
      final positions = CourierDispatchQueueBuilder.build([
        _entered(
            id: '2',
            courierId: 'ahmet',
            occurredAt: DateTime(2026, 1, 1, 10, 30)),
        _left(
            id: '1',
            courierId: 'ahmet',
            occurredAt: DateTime(2026, 1, 1, 10, 0)),
      ]);
      expect(positions.single.courierId, 'ahmet');
    });

    test('no events at all produces an empty queue', () {
      expect(CourierDispatchQueueBuilder.build([]), isEmpty);
    });
  });
}
