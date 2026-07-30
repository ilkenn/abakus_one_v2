import '../../../../core/utils/clock.dart';
import '../../data/courier_fraud_signal_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/fraud/courier_fraud_signal.dart';
import '../../domain/fraud/courier_fraud_signal_detector.dart';
import '../../domain/fraud/courier_fraud_signal_type.dart';
import '../../domain/location/courier_location_snapshot.dart';
import '../identity/courier_fraud_signal_id_generator.dart';

/// Runs every per-reading pure detector
/// ([CourierFraudSignalDetector.detectImpossibleSpeed]/`detectGpsJump`/
/// `detectUnrealisticTravel`/`detectMockLocation`) against one fresh
/// [CourierLocationSnapshot] and its immediate predecessor, persisting any
/// triggered signals — Sprint 5B Part 8.
///
/// **Never blocks, never throws a business-rule violation, never gates
/// anything** — "generate operational signals only, do NOT implement
/// punishment." System-triggered, no authorization gate (mirrors
/// `RecordCourierLocationSnapshot`'s own precedent: routine device-
/// telemetry processing).
class DetectCourierFraudSignals {
  const DetectCourierFraudSignals({
    required Clock clock,
    required CourierFraudSignalIdGenerator idGenerator,
    required CourierFraudSignalRepository repository,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final CourierFraudSignalIdGenerator _idGenerator;
  final CourierFraudSignalRepository _repository;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<List<CourierFraudSignal>> call({
    required String branchId,
    required CourierLocationSnapshot current,
    CourierLocationSnapshot? previous,
  }) async {
    final triggered = <CourierFraudSignalType>[
      if (previous != null) ...[
        if (CourierFraudSignalDetector.detectImpossibleSpeed(
              previous: previous,
              current: current,
            ) !=
            null)
          CourierFraudSignalType.impossibleSpeed,
        if (CourierFraudSignalDetector.detectGpsJump(
              previous: previous,
              current: current,
            ) !=
            null)
          CourierFraudSignalType.gpsJump,
        if (CourierFraudSignalDetector.detectUnrealisticTravel(
              windowStart: previous,
              windowEnd: current,
            ) !=
            null)
          CourierFraudSignalType.unrealisticTravelDistance,
      ],
      if (CourierFraudSignalDetector.detectMockLocation(current) != null)
        CourierFraudSignalType.mockLocationDetected,
    ];

    final now = _clock.now();
    final signals = <CourierFraudSignal>[];
    for (final type in triggered) {
      final signal = CourierFraudSignal(
        id: _idGenerator.nextSignalId(),
        courierId: current.courierId,
        deviceId: current.deviceId,
        type: type,
        description: 'Fraud signal detected: ${type.name}',
        evidenceSnapshotId: current.id,
        detectedAt: now,
      );
      await _repository.append(signal);
      await _auditRepository.appendEvent(CourierOperationalAuditEntry(
        id: '${signal.id}-audit',
        branchId: branchId,
        actorStaffId: 'system',
        courierId: current.courierId,
        deviceId: current.deviceId,
        type: CourierAuditEventType.fraudSignalDetected,
        description: signal.description,
        timestamp: now,
        locationRef: current.id,
        correlationId: signal.id,
      ));
      signals.add(signal);
    }
    return signals;
  }
}
