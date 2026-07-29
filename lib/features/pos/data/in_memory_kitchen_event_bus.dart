import 'dart:async';

import '../domain/kds/kitchen_event.dart';
import '../domain/kds/kitchen_event_publisher.dart';
import '../domain/kds/kitchen_event_subscriber.dart';

/// The only [KitchenEventPublisher]/[KitchenEventSubscriber] implementation
/// this phase — an in-process, per-branch broadcast stream. Delivers every
/// published event to every currently-subscribed listener, in publish
/// order, within one running app instance.
///
/// **Not real cross-device/cross-process real-time infrastructure** — a
/// second device (a second Flutter instance, or the same app after a
/// restart) never receives events published before it subscribed, and two
/// separate process instances never see each other's events at all. This
/// is the honestly-reported boundary `docs/decisions.md` ADR-016 records:
/// reconnect/catch-up correctness always goes through
/// `KitchenSynchronizationService`'s cursor-based replay against
/// `KitchenEventRepository`, never through this bus alone.
class InMemoryKitchenEventBus
    implements KitchenEventPublisher, KitchenEventSubscriber {
  final Map<String, StreamController<KitchenEvent>> _controllersByBranch = {};

  StreamController<KitchenEvent> _controllerFor(String branchId) {
    return _controllersByBranch.putIfAbsent(
      branchId,
      () => StreamController<KitchenEvent>.broadcast(),
    );
  }

  @override
  Future<void> publish(KitchenEvent event) async {
    _controllerFor(event.branchId).add(event);
  }

  @override
  Stream<KitchenEvent> subscribe({required String branchId}) {
    return _controllerFor(branchId).stream;
  }

  /// Test/lifecycle cleanup — not part of either interface.
  Future<void> closeAll() async {
    for (final controller in _controllersByBranch.values) {
      await controller.close();
    }
    _controllersByBranch.clear();
  }
}
