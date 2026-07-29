/// One point-in-time courier position reading. **Never treated as
/// definitive evidence on its own** — [accuracyMeters] must always be
/// considered by any consumer (see `GeofenceEvaluator`). Immutable,
/// append-only — a new reading is always a new snapshot.
class CourierLocationSnapshot {
  const CourierLocationSnapshot({
    required this.id,
    required this.courierId,
    required this.deviceId,
    this.shiftId,
    this.deliveryId,
    required this.latitude,
    required this.longitude,
    required this.accuracyMeters,
    this.headingDegrees,
    this.speedMetersPerSecond,
    required this.capturedAt,
    required this.receivedAt,
  });

  final String id;
  final String courierId;
  final String deviceId;
  final String? shiftId;
  final String? deliveryId;

  final double latitude;
  final double longitude;

  /// Horizontal accuracy radius in meters, as reported by the device's
  /// location provider — the single most important field for any
  /// downstream evaluation ("do not treat low-accuracy GPS as definitive
  /// evidence").
  final double accuracyMeters;

  final double? headingDegrees;
  final double? speedMetersPerSecond;

  /// When the device actually captured this fix.
  final DateTime capturedAt;

  /// When the backend/app received it — may lag [capturedAt] under poor
  /// connectivity (an offline-queued snapshot synced later).
  final DateTime receivedAt;
}
