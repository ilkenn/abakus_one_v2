import 'courier_location_snapshot.dart';
import 'location_tracking_accuracy.dart';

/// Backend-neutral source of location readings for one courier device.
/// **Sprint 5B**: `GeolocatorCourierLocationProvider`
/// (`lib/features/courier/data/geolocator_courier_location_provider.dart`)
/// is the first real, platform-backed implementation, wrapping the
/// `geolocator` package — this interface itself is unchanged in shape
/// from Phase 5 (`watch`), plus one additive method this sprint
/// ([current]) for a one-shot fix. [NoOpCourierLocationProvider] remains
/// the honest "never produces a reading" default for tests/environments
/// with no real device.
abstract interface class CourierLocationProvider {
  Stream<CourierLocationSnapshot> watch({
    required String courierId,
    required String deviceId,
    LocationTrackingAccuracy accuracy = LocationTrackingAccuracy.balanced,
    Duration? interval,
    double? distanceFilterMeters,
  });

  /// A single, on-demand fix — "current location," distinct from the
  /// continuous [watch] stream. Returns `null` if no fix could be
  /// obtained (permission denied, service disabled, or timeout).
  Future<CourierLocationSnapshot?> current({
    required String courierId,
    required String deviceId,
  });
}

class NoOpCourierLocationProvider implements CourierLocationProvider {
  const NoOpCourierLocationProvider();

  @override
  Stream<CourierLocationSnapshot> watch({
    required String courierId,
    required String deviceId,
    LocationTrackingAccuracy accuracy = LocationTrackingAccuracy.balanced,
    Duration? interval,
    double? distanceFilterMeters,
  }) =>
      const Stream.empty();

  @override
  Future<CourierLocationSnapshot?> current({
    required String courierId,
    required String deviceId,
  }) async =>
      null;
}
