import '../availability/courier_availability_status.dart';
import 'courier_location_availability.dart';
import 'movement_state.dart';
import 'signal_quality.dart';

/// One courier's assembled live-tracking read model — Sprint 5B Part 6.
/// Built fresh on every read by `BuildCourierLiveStatus`, never persisted
/// itself (it's a projection over `CourierLocationRepository`/
/// `CourierConnectionMonitor`/`CourierAvailabilityRepository`/
/// `CourierLocationAvailabilityRepository`/`DeliveryRepository`, all of
/// which remain the actual source of truth).
class CourierLiveStatus {
  const CourierLiveStatus({
    required this.courierId,
    required this.branchId,
    required this.isOnline,
    required this.availabilityStatus,
    this.locationAvailabilityStatus,
    this.latitude,
    this.longitude,
    this.headingDegrees,
    this.speedMetersPerSecond,
    this.movementState,
    this.signalQuality,
    this.accuracyMeters,
    this.batteryLevelPercent,
    this.lastLocationUpdateAt,
    this.activeDeliveryId,
  });

  final String courierId;
  final String branchId;

  /// Derived from `CourierConnectionMonitor.isStale` on the courier's most
  /// recent reporting device — `false` (offline) whenever there is no
  /// location reading on record at all.
  final bool isOnline;

  final CourierAvailabilityStatus availabilityStatus;
  final CourierLocationAvailabilityStatus? locationAvailabilityStatus;

  final double? latitude;
  final double? longitude;
  final double? headingDegrees;
  final double? speedMetersPerSecond;
  final MovementState? movementState;
  final SignalQuality? signalQuality;
  final double? accuracyMeters;
  final int? batteryLevelPercent;
  final DateTime? lastLocationUpdateAt;

  /// `null` when the courier has no delivery currently in progress.
  final String? activeDeliveryId;

  /// `true` when there is no location reading on record at all — the
  /// manager UI's cue to show "konum verisi yok" rather than a stale pin.
  bool get hasNeverReportedLocation => latitude == null || longitude == null;
}
