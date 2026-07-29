import 'dart:async';

import '../domain/events/courier_event.dart';
import '../domain/events/courier_event_publisher.dart';
import '../domain/events/courier_event_subscriber.dart';

/// The only [CourierEventPublisher]/[CourierEventSubscriber] implementation
/// this phase — mirrors `InMemoryKitchenEventBus`'s shape and same honest
/// boundary: same-process, per-branch broadcast only, **not real cross-
/// device/cross-process real-time delivery** (see `docs/decisions.md`
/// ADR-017).
class InMemoryCourierEventBus
    implements CourierEventPublisher, CourierEventSubscriber {
  final Map<String, StreamController<CourierEvent>> _controllersByBranch = {};

  StreamController<CourierEvent> _controllerFor(String branchId) {
    return _controllersByBranch.putIfAbsent(
      branchId,
      () => StreamController<CourierEvent>.broadcast(),
    );
  }

  @override
  Future<void> publish(CourierEvent event) async {
    _controllerFor(event.branchId).add(event);
  }

  @override
  Stream<CourierEvent> subscribe({required String branchId}) {
    return _controllerFor(branchId).stream;
  }

  Future<void> closeAll() async {
    for (final controller in _controllersByBranch.values) {
      await controller.close();
    }
    _controllersByBranch.clear();
  }
}
