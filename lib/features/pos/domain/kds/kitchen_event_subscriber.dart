import 'kitchen_event.dart';

/// Subscribes to a branch's live [KitchenEvent] stream — the read side of
/// [KitchenEventPublisher]. Same backend-neutrality and
/// in-memory-only-this-phase boundary applies (see that interface's doc
/// comment).
///
/// A subscriber is a convenience for "notify me as events happen"; it is
/// never the only way to catch up — `KitchenSynchronizationService`'s
/// cursor-based replay is what a reconnecting device actually relies on
/// for correctness, since a `Stream` can silently miss events during a
/// disconnection window.
abstract interface class KitchenEventSubscriber {
  Stream<KitchenEvent> subscribe({required String branchId});
}
