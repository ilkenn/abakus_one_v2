import '../../../../core/utils/clock.dart';
import '../../data/courier_fraud_signal_repository.dart';
import '../../data/courier_location_availability_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/fraud/courier_fraud_signal.dart';
import '../../domain/fraud/courier_fraud_signal_type.dart';
import '../../domain/location/location_unavailable_reason.dart';
import '../identity/courier_fraud_signal_id_generator.dart';

/// Counts [LocationUnavailableReason] occurrences in a courier's
/// `CourierLocationAvailability` history within [window] — Sprint 5B Part
/// 8's `repeatedGpsLoss` (from [LocationUnavailableReason.signalLost])
/// and `backgroundTrackingDisabled` (from
/// [LocationUnavailableReason.backgroundBlocked]) signals. Call this
/// after `ReportCourierLocationAvailability` records a new unavailable
/// reason — this use case never writes to `CourierLocationAvailability`
/// itself, only reads its history.
///
/// Same non-punitive contract as `DetectCourierFraudSignals`: generates
/// signals only, never blocks or gates anything.
class DetectRepeatedLocationLossSignal {
  const DetectRepeatedLocationLossSignal({
    required Clock clock,
    required CourierLocationAvailabilityRepository availabilityRepository,
    required CourierFraudSignalIdGenerator idGenerator,
    required CourierFraudSignalRepository repository,
    required CourierOperationalAuditEntryRepository auditRepository,
    this.window = const Duration(hours: 1),
    this.minimumOccurrences = 3,
  })  : _clock = clock,
        _availabilityRepository = availabilityRepository,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final CourierLocationAvailabilityRepository _availabilityRepository;
  final CourierFraudSignalIdGenerator _idGenerator;
  final CourierFraudSignalRepository _repository;
  final CourierOperationalAuditEntryRepository _auditRepository;

  /// The lookback window an occurrence count is evaluated over —
  /// adjustable, never hardcoded inline.
  final Duration window;

  /// Occurrences within [window] at or above this count trigger a signal.
  final int minimumOccurrences;

  Future<CourierFraudSignal?> call({
    required String branchId,
    required String courierId,
    required String deviceId,
    required LocationUnavailableReason reason,
  }) async {
    if (reason != LocationUnavailableReason.signalLost &&
        reason != LocationUnavailableReason.backgroundBlocked) {
      return null;
    }

    final now = _clock.now();
    final history =
        await _availabilityRepository.findHistoryByCourierId(courierId);
    final occurrences = history.where(
        (a) => a.reason == reason && now.difference(a.updatedAt) <= window);
    if (occurrences.length < minimumOccurrences) return null;

    final type = reason == LocationUnavailableReason.signalLost
        ? CourierFraudSignalType.repeatedGpsLoss
        : CourierFraudSignalType.backgroundTrackingDisabled;

    final signal = CourierFraudSignal(
      id: _idGenerator.nextSignalId(),
      courierId: courierId,
      deviceId: deviceId,
      type: type,
      description:
          '${occurrences.length}x ${reason.name} within ${window.inMinutes} dk',
      detectedAt: now,
    );
    await _repository.append(signal);
    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${signal.id}-audit',
      branchId: branchId,
      actorStaffId: 'system',
      courierId: courierId,
      deviceId: deviceId,
      type: CourierAuditEventType.fraudSignalDetected,
      description: signal.description,
      timestamp: now,
      correlationId: signal.id,
    ));
    return signal;
  }
}
