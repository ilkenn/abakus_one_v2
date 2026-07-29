import '../../../../core/utils/clock.dart';
import '../../data/courier_location_repository.dart';
import '../../data/geofence_transition_event_repository.dart';
import '../../domain/location/courier_location_snapshot.dart';
import '../../domain/location/geofence_evaluator.dart';
import '../../domain/location/geofence_transition_detector.dart';
import '../../domain/location/geofence_transition_event.dart';
import '../../domain/location/geofence_zone.dart';
import '../../domain/location/multi_geofence_evaluator.dart';
import '../identity/geofence_transition_event_id_generator.dart';

/// Evaluates one fresh [CourierLocationSnapshot] against every currently
/// active [GeofenceZone] for a delivery (restaurant/pickup/customer —
/// "multiple simultaneous geofences"), confirms any genuine entry/exit via
/// [GeofenceTransitionDetector], and appends confirmed transitions to the
/// geofence history. Sprint 5B Part 4.
///
/// The "previous" reading compared against for each zone is the most
/// recent snapshot on record for this delivery captured strictly before
/// [snapshot] — found via the unmodified `CourierLocationRepository`,
/// never a separately-tracked "last known state." [snapshot] itself does
/// not need to already be persisted when this is called.
///
/// No authorization gate — like `RecordCourierLocationSnapshot`, this is
/// routine device-telemetry processing, not a privileged action.
class EvaluateCourierGeofences {
  const EvaluateCourierGeofences({
    required Clock clock,
    required CourierLocationRepository locationRepository,
    required GeofenceTransitionEventRepository transitionRepository,
    required GeofenceTransitionEventIdGenerator idGenerator,
  })  : _clock = clock,
        _locationRepository = locationRepository,
        _transitionRepository = transitionRepository,
        _idGenerator = idGenerator;

  final Clock _clock;
  final CourierLocationRepository _locationRepository;
  final GeofenceTransitionEventRepository _transitionRepository;
  final GeofenceTransitionEventIdGenerator _idGenerator;

  Future<List<GeofenceTransitionEvent>> call({
    required String deliveryId,
    required String courierId,
    required CourierLocationSnapshot snapshot,
    required List<GeofenceZone> zones,
  }) async {
    if (zones.isEmpty) return const [];

    final history = await _locationRepository.findByDeliveryId(deliveryId);
    final previousSnapshot = _findPrevious(history, snapshot);

    final evaluations = MultiGeofenceEvaluator.evaluate(
      snapshot: snapshot,
      zones: zones,
    );

    final now = _clock.now();
    final confirmed = <GeofenceTransitionEvent>[];
    for (final evaluation in evaluations) {
      final previousResult = previousSnapshot == null
          ? null
          : GeofenceEvaluator.evaluate(
              snapshot: previousSnapshot,
              targetLatitude: evaluation.zone.targetLatitude,
              targetLongitude: evaluation.zone.targetLongitude,
              radiusMeters: evaluation.zone.radiusMeters,
            );

      final transition = GeofenceTransitionDetector.detect(
        previous: previousResult,
        current: evaluation.result,
      );
      if (transition == null) continue;

      final event = GeofenceTransitionEvent(
        id: _idGenerator.nextTransitionId(),
        deliveryId: deliveryId,
        courierId: courierId,
        zoneType: evaluation.zone.zoneType,
        transitionType: transition,
        snapshotId: snapshot.id,
        distanceMeters: evaluation.result.distanceMeters,
        occurredAt: now,
      );
      await _transitionRepository.append(event);
      confirmed.add(event);
    }
    return confirmed;
  }

  static CourierLocationSnapshot? _findPrevious(
    List<CourierLocationSnapshot> history,
    CourierLocationSnapshot snapshot,
  ) {
    CourierLocationSnapshot? previous;
    for (final candidate in history) {
      if (candidate.id == snapshot.id) continue;
      if (!candidate.capturedAt.isBefore(snapshot.capturedAt)) continue;
      if (previous == null ||
          candidate.capturedAt.isAfter(previous.capturedAt)) {
        previous = candidate;
      }
    }
    return previous;
  }
}
