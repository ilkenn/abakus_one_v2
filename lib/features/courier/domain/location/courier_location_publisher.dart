import 'courier_location_snapshot.dart';

/// Publishes a captured [CourierLocationSnapshot] onward (to storage
/// and/or a live subscriber) — backend-neutral, mirrors
/// `KitchenEventPublisher`'s shape and same-process-only boundary this
/// phase.
abstract interface class CourierLocationPublisher {
  Future<void> publish(CourierLocationSnapshot snapshot);
}
