import 'geofence_transition_type.dart';
import 'geofence_zone_type.dart';

/// One confirmed geofence entry/exit — Sprint 5B Part 4's "geofence
/// history." Immutable, append-only, one record per confirmed transition
/// (never per raw reading — see [GeofenceTransitionDetector]).
class GeofenceTransitionEvent {
  const GeofenceTransitionEvent({
    required this.id,
    required this.deliveryId,
    required this.courierId,
    required this.zoneType,
    required this.transitionType,
    required this.snapshotId,
    required this.distanceMeters,
    required this.occurredAt,
  });

  final String id;
  final String deliveryId;
  final String courierId;
  final GeofenceZoneType zoneType;
  final GeofenceTransitionType transitionType;

  /// The [CourierLocationSnapshot.id] whose reading confirmed this
  /// transition — the evidentiary record this event is derived from.
  final String snapshotId;
  final double distanceMeters;
  final DateTime occurredAt;
}
