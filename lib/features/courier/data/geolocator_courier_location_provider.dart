import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart' as geo;

import '../../../core/utils/clock.dart';
import '../application/identity/courier_location_snapshot_id_generator.dart';
import '../domain/location/courier_location_provider.dart';
import '../domain/location/courier_location_snapshot.dart';
import '../domain/location/location_tracking_accuracy.dart';

/// Real, device-backed [CourierLocationProvider] — Sprint 5B Part 1.
/// Wraps `package:geolocator`'s position stream/one-shot fix APIs and maps
/// its [geo.Position] into the domain's platform-neutral
/// [CourierLocationSnapshot]. No `geolocator` type crosses this file's
/// boundary into the domain layer.
///
/// [id] on every emitted snapshot is generated locally by [_idGenerator] —
/// it identifies this device-side reading only. The eventual persisted
/// record (via `RecordCourierLocationSnapshot`) always assigns its own id
/// from the repository-side sequence; this local id is never assumed to
/// match it.
class GeolocatorCourierLocationProvider implements CourierLocationProvider {
  GeolocatorCourierLocationProvider({
    required Clock clock,
    required CourierLocationSnapshotIdGenerator idGenerator,
  })  : _clock = clock,
        _idGenerator = idGenerator;

  final Clock _clock;
  final CourierLocationSnapshotIdGenerator _idGenerator;

  static geo.LocationAccuracy _mapAccuracy(LocationTrackingAccuracy accuracy) {
    switch (accuracy) {
      case LocationTrackingAccuracy.high:
        return geo.LocationAccuracy.best;
      case LocationTrackingAccuracy.balanced:
        return geo.LocationAccuracy.medium;
      case LocationTrackingAccuracy.low:
        return geo.LocationAccuracy.low;
    }
  }

  static geo.LocationSettings _buildSettings({
    required LocationTrackingAccuracy accuracy,
    Duration? interval,
    double? distanceFilterMeters,
  }) {
    final geoAccuracy = _mapAccuracy(accuracy);
    final distanceFilter = distanceFilterMeters?.round() ?? 0;

    if (defaultTargetPlatform == TargetPlatform.android) {
      return geo.AndroidSettings(
        accuracy: geoAccuracy,
        distanceFilter: distanceFilter,
        intervalDuration: interval,
      );
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return geo.AppleSettings(
        accuracy: geoAccuracy,
        distanceFilter: distanceFilter,
        // Foreground-only here — sustained background delivery is
        // `GeolocatorBackgroundLocationSession`'s explicit responsibility,
        // never implicit in the general-purpose provider.
        allowBackgroundLocationUpdates: false,
      );
    }
    return geo.LocationSettings(
      accuracy: geoAccuracy,
      distanceFilter: distanceFilter,
    );
  }

  CourierLocationSnapshot _toSnapshot({
    required String courierId,
    required String deviceId,
    required geo.Position position,
  }) {
    return CourierLocationSnapshot(
      id: _idGenerator.nextSnapshotId(),
      courierId: courierId,
      deviceId: deviceId,
      latitude: position.latitude,
      longitude: position.longitude,
      accuracyMeters: position.accuracy,
      headingDegrees: position.heading,
      speedMetersPerSecond: position.speed,
      altitudeMeters: position.altitude,
      isMocked: position.isMocked,
      capturedAt: position.timestamp,
      receivedAt: _clock.now(),
    );
  }

  @override
  Stream<CourierLocationSnapshot> watch({
    required String courierId,
    required String deviceId,
    LocationTrackingAccuracy accuracy = LocationTrackingAccuracy.balanced,
    Duration? interval,
    double? distanceFilterMeters,
  }) {
    final settings = _buildSettings(
      accuracy: accuracy,
      interval: interval,
      distanceFilterMeters: distanceFilterMeters,
    );
    return geo.Geolocator.getPositionStream(locationSettings: settings).map(
      (position) => _toSnapshot(
        courierId: courierId,
        deviceId: deviceId,
        position: position,
      ),
    );
  }

  @override
  Future<CourierLocationSnapshot?> current({
    required String courierId,
    required String deviceId,
  }) async {
    try {
      final position = await geo.Geolocator.getCurrentPosition(
        locationSettings: _buildSettings(
          accuracy: LocationTrackingAccuracy.high,
        ),
      );
      return _toSnapshot(
        courierId: courierId,
        deviceId: deviceId,
        position: position,
      );
    } on geo.LocationServiceDisabledException {
      return null;
    } on geo.PermissionDeniedException {
      return null;
    } on geo.PositionUpdateException {
      return null;
    }
  }
}
