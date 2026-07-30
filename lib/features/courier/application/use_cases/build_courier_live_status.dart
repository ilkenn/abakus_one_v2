import '../../../../core/utils/clock.dart';
import '../../data/courier_availability_repository.dart';
import '../../data/courier_location_availability_repository.dart';
import '../../data/courier_location_repository.dart';
import '../../data/delivery_repository.dart';
import '../../domain/availability/courier_availability_status.dart';
import '../../domain/events/courier_connection_monitor.dart';
import '../../domain/location/adaptive_tracking_policy.dart';
import '../../domain/location/courier_live_status.dart';
import '../../domain/location/signal_quality.dart';

/// Assembles one courier's [CourierLiveStatus] from the existing,
/// unmodified location/availability/delivery repositories — Sprint 5B
/// Part 6. A pure read-model builder: no I/O beyond the repository reads
/// it needs, no authorization check (matches `BuildCourierEarningsSummary`
/// /`BuildCourierPerformanceSnapshot`'s existing precedent — reachability
/// of the *screen* that calls this is the access gate, same as
/// `CourierDispatchBoardScreen`'s established pattern).
class BuildCourierLiveStatus {
  const BuildCourierLiveStatus({
    required Clock clock,
    required CourierLocationRepository locationRepository,
    required CourierConnectionMonitor connectionMonitor,
    required CourierAvailabilityRepository availabilityRepository,
    required CourierLocationAvailabilityRepository
        locationAvailabilityRepository,
    required DeliveryRepository deliveryRepository,
    this.trackingPolicy = const AdaptiveTrackingPolicy(),
    this.staleAfter = const Duration(seconds: 90),
  })  : _clock = clock,
        _locationRepository = locationRepository,
        _connectionMonitor = connectionMonitor,
        _availabilityRepository = availabilityRepository,
        _locationAvailabilityRepository = locationAvailabilityRepository,
        _deliveryRepository = deliveryRepository;

  final Clock _clock;
  final CourierLocationRepository _locationRepository;
  final CourierConnectionMonitor _connectionMonitor;
  final CourierAvailabilityRepository _availabilityRepository;
  final CourierLocationAvailabilityRepository _locationAvailabilityRepository;
  final DeliveryRepository _deliveryRepository;

  final AdaptiveTrackingPolicy trackingPolicy;

  /// No location update within this window is considered offline —
  /// adjustable, never hardcoded inline in [call].
  final Duration staleAfter;

  Future<CourierLiveStatus> call({
    required String courierId,
    required String branchId,
  }) async {
    final now = _clock.now();
    final latestSnapshot =
        await _locationRepository.findLatestByCourierId(courierId);
    final availability =
        await _availabilityRepository.findByCourierId(courierId);
    final locationAvailability =
        await _locationAvailabilityRepository.findLatestByCourierId(courierId);
    final activeDeliveries =
        await _deliveryRepository.findActiveByCourierId(courierId);

    final isOnline = latestSnapshot == null
        ? false
        : !(await _connectionMonitor.isStale(
            deviceId: latestSnapshot.deviceId,
            staleAfter: staleAfter,
            now: now,
          ));

    final speed = latestSnapshot?.speedMetersPerSecond;

    return CourierLiveStatus(
      courierId: courierId,
      branchId: branchId,
      isOnline: isOnline,
      availabilityStatus:
          availability?.status ?? CourierAvailabilityStatus.offline,
      locationAvailabilityStatus: locationAvailability?.status,
      latitude: latestSnapshot?.latitude,
      longitude: latestSnapshot?.longitude,
      headingDegrees: latestSnapshot?.headingDegrees,
      speedMetersPerSecond: speed,
      movementState: speed == null
          ? null
          : trackingPolicy.classify(speedMetersPerSecond: speed),
      signalQuality: latestSnapshot == null
          ? null
          : SignalQualityClassifier.classify(latestSnapshot.accuracyMeters),
      accuracyMeters: latestSnapshot?.accuracyMeters,
      batteryLevelPercent: latestSnapshot?.batteryLevelPercent,
      lastLocationUpdateAt: latestSnapshot?.receivedAt,
      activeDeliveryId:
          activeDeliveries.isEmpty ? null : activeDeliveries.first.id,
      activeDeliveryIds: [for (final d in activeDeliveries) d.id],
    );
  }
}
