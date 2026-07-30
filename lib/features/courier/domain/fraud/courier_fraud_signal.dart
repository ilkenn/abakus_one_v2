import 'courier_fraud_signal_type.dart';

/// One recorded fraud signal — Sprint 5B Part 8. Immutable, append-only.
/// Deliberately carries **no enforcement field of any kind** (no
/// `blocked`, no `severity`-driven action, no punishment): "generate
/// operational signals only, do NOT implement punishment" is satisfied
/// structurally — there is nothing on this type any caller could even
/// wire into a block/ban/deny decision.
class CourierFraudSignal {
  const CourierFraudSignal({
    required this.id,
    required this.courierId,
    required this.deviceId,
    required this.type,
    required this.description,
    this.evidenceSnapshotId,
    required this.detectedAt,
  });

  final String id;
  final String courierId;
  final String deviceId;
  final CourierFraudSignalType type;
  final String description;

  /// The [CourierLocationSnapshot.id] (or the more recent of a pair, for
  /// two-point detectors) that triggered this signal — the evidentiary
  /// trail for whatever future Risk Engine consumes these.
  final String? evidenceSnapshotId;
  final DateTime detectedAt;
}
