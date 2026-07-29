import '../domain/location/geofence_transition_event.dart';

/// Append-only storage for [GeofenceTransitionEvent] — Sprint 5B's
/// geofence entry/exit history.
abstract interface class GeofenceTransitionEventRepository {
  Future<void> append(GeofenceTransitionEvent event);
  Future<List<GeofenceTransitionEvent>> findByDeliveryId(String deliveryId);
}

class InMemoryGeofenceTransitionEventRepository
    implements GeofenceTransitionEventRepository {
  final List<GeofenceTransitionEvent> _events = [];

  @override
  Future<void> append(GeofenceTransitionEvent event) async {
    _events.add(event);
  }

  @override
  Future<List<GeofenceTransitionEvent>> findByDeliveryId(
      String deliveryId) async {
    return List.unmodifiable(
      _events.where((e) => e.deliveryId == deliveryId),
    );
  }
}
