import 'courier_event.dart';

/// Subscribes to a branch's live [CourierEvent] stream — the read side of
/// [CourierEventPublisher]. As with `KitchenEventSubscriber`, correctness
/// for a reconnecting device always relies on `CourierSynchronizationService`'s
/// cursor-based replay, never this stream alone.
abstract interface class CourierEventSubscriber {
  Stream<CourierEvent> subscribe({required String branchId});
}
