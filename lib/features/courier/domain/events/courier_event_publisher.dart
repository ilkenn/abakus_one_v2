import 'courier_event.dart';

/// Publishes a [CourierEvent] to every interested subscriber — backend-
/// neutral, mirrors `KitchenEventPublisher`'s shape and same-process-only
/// boundary this phase (see `docs/decisions.md` ADR-017).
abstract interface class CourierEventPublisher {
  Future<void> publish(CourierEvent event);
}
