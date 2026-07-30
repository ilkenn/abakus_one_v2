import 'dart:math' as math;

import '../location/courier_location_snapshot.dart';
import 'courier_fraud_signal_type.dart';

/// Pure, stateless detectors over pairs (or single readings) of
/// [CourierLocationSnapshot] — Sprint 5B Part 8. Mirrors
/// `GeofenceTransitionDetector`'s shape: no I/O, returns a nullable
/// trigger, every threshold is a parameter (never hardcoded).
abstract final class CourierFraudSignalDetector {
  CourierFraudSignalDetector._();

  static const double _earthRadiusMeters = 6371000;

  static double _distanceMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLat = _rad(lat2 - lat1);
    final dLon = _rad(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_rad(lat1)) *
            math.cos(_rad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return _earthRadiusMeters * c;
  }

  static double _rad(double d) => d * math.pi / 180;

  /// Instantaneous speed between two consecutive readings exceeding
  /// [maxRealisticSpeedMetersPerSecond] (default ~200 km/h — well above
  /// any legitimate delivery vehicle). Requires both readings to have
  /// trusted accuracy — a low-accuracy jump is `gpsJump`'s concern, not a
  /// speed claim this detector should make.
  static CourierFraudSignalType? detectImpossibleSpeed({
    required CourierLocationSnapshot previous,
    required CourierLocationSnapshot current,
    double maxRealisticSpeedMetersPerSecond = 55,
    double maxTrustedAccuracyMeters = 50,
  }) {
    if (previous.accuracyMeters > maxTrustedAccuracyMeters ||
        current.accuracyMeters > maxTrustedAccuracyMeters) {
      return null;
    }
    final seconds =
        current.capturedAt.difference(previous.capturedAt).inMilliseconds /
            1000;
    if (seconds <= 0) return null;
    final distance = _distanceMeters(
      previous.latitude,
      previous.longitude,
      current.latitude,
      current.longitude,
    );
    final speed = distance / seconds;
    return speed > maxRealisticSpeedMetersPerSecond
        ? CourierFraudSignalType.impossibleSpeed
        : null;
  }

  /// A large position jump within a very short time window —
  /// deliberately distinct from [detectImpossibleSpeed]: this catches the
  /// degenerate near-zero-elapsed-time case (where a speed calculation is
  /// undefined/explosive) as its own named signal, per the brief's own
  /// separate "GPS jump" entry.
  static CourierFraudSignalType? detectGpsJump({
    required CourierLocationSnapshot previous,
    required CourierLocationSnapshot current,
    double minJumpDistanceMeters = 500,
    Duration maxWindow = const Duration(seconds: 5),
  }) {
    final elapsed = current.capturedAt.difference(previous.capturedAt);
    if (elapsed <= Duration.zero || elapsed > maxWindow) return null;
    final distance = _distanceMeters(
      previous.latitude,
      previous.longitude,
      current.latitude,
      current.longitude,
    );
    return distance >= minJumpDistanceMeters
        ? CourierFraudSignalType.gpsJump
        : null;
  }

  /// Cumulative distance across a reading window that exceeds what's
  /// physically plausible for the elapsed time, at
  /// [maxSustainedSpeedMetersPerSecond] — a coarser, longer-window
  /// cousin of [detectImpossibleSpeed] (catches many small, individually-
  /// plausible-looking jumps that add up to an implausible total).
  static CourierFraudSignalType? detectUnrealisticTravel({
    required CourierLocationSnapshot windowStart,
    required CourierLocationSnapshot windowEnd,
    double maxSustainedSpeedMetersPerSecond = 33,
  }) {
    final seconds =
        windowEnd.capturedAt.difference(windowStart.capturedAt).inMilliseconds /
            1000;
    if (seconds <= 0) return null;
    final distance = _distanceMeters(
      windowStart.latitude,
      windowStart.longitude,
      windowEnd.latitude,
      windowEnd.longitude,
    );
    final impliedSpeed = distance / seconds;
    return impliedSpeed > maxSustainedSpeedMetersPerSecond
        ? CourierFraudSignalType.unrealisticTravelDistance
        : null;
  }

  /// [CourierLocationSnapshot.isMocked] is already the platform's own
  /// mock-location signal (Android only) — this detector exists only to
  /// give it a uniform place alongside every other fraud signal, not to
  /// add new logic on top of it.
  static CourierFraudSignalType? detectMockLocation(
    CourierLocationSnapshot snapshot,
  ) {
    return snapshot.isMocked
        ? CourierFraudSignalType.mockLocationDetected
        : null;
  }
}
