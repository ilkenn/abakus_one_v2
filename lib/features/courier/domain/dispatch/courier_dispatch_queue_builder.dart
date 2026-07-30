import 'courier_dispatch_queue_event.dart';
import 'courier_dispatch_queue_position.dart';

/// Projects the append-only [CourierDispatchQueueEvent] log into the
/// current FIFO queue order — Sprint 5C. A pure, stateless calculator, no
/// I/O — mirrors `GeofenceEvaluator`/`AdaptiveTrackingPolicy`'s shape.
///
/// For each courier, only the most recent event (by [occurredAt], ties
/// broken by list order — the log's own append order) decides membership:
/// a courier whose latest event is [CourierDispatchQueueEventType.entered]
/// is in the queue, ranked by that event's [occurredAt] — "the first
/// courier arriving becomes first in queue," and re-entering after a
/// delivery/break always means a fresh, later `entered` event, so "return
/// to queue fairly" (never jumping ahead of couriers already waiting) is
/// structural, not a rule this builder has to special-case.
abstract final class CourierDispatchQueueBuilder {
  CourierDispatchQueueBuilder._();

  static List<CourierDispatchQueuePosition> build(
    List<CourierDispatchQueueEvent> events,
  ) {
    final sorted = [...events]
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    final latestByCourier = <String, CourierDispatchQueueEvent>{};
    for (final event in sorted) {
      latestByCourier[event.courierId] = event;
    }

    final inQueue = latestByCourier.values
        .where((e) => e.type == CourierDispatchQueueEventType.entered)
        .toList()
      ..sort((a, b) => a.occurredAt.compareTo(b.occurredAt));

    return [
      for (var i = 0; i < inQueue.length; i++)
        CourierDispatchQueuePosition(
          courierId: inQueue[i].courierId,
          position: i + 1,
          enteredQueueAt: inQueue[i].occurredAt,
        ),
    ];
  }
}
