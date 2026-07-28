import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/cash_audit_entry_repository.dart';
import '../../data/cash_movement_repository.dart';
import '../../data/cash_session_repository.dart';
import '../../domain/cash/cash_audit_entry.dart';
import '../../domain/cash/cash_audit_event_type.dart';
import '../../domain/cash/cash_movement.dart';
import '../../domain/cash/cash_movement_type.dart';
import '../../domain/cash/cash_session_status.dart';
import '../identity/cash_movement_id_generator.dart';

/// Reverses an already-recorded [CashMovement] by appending a new,
/// offsetting `CashMovementType.correction` entry — the original movement
/// is never mutated or deleted (`docs/business_rules.md`: all movements
/// immutable, no delete operations).
///
/// Throws [UnknownCashEntityViolation] if [movementId] doesn't resolve or
/// doesn't belong to [sessionId], or [CashSessionNotActiveViolation] if
/// the session isn't currently active.
class ReverseCashMovement {
  const ReverseCashMovement({
    required Clock clock,
    required CashMovementIdGenerator idGenerator,
    required CashSessionRepository sessionRepository,
    required CashMovementRepository movementRepository,
    required CashAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _sessionRepository = sessionRepository,
        _movementRepository = movementRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final CashMovementIdGenerator _idGenerator;
  final CashSessionRepository _sessionRepository;
  final CashMovementRepository _movementRepository;
  final CashAuditEntryRepository _auditRepository;

  Future<CashMovement> call({
    required String sessionId,
    required String movementId,
    required String reason,
    required String actorStaffId,
  }) async {
    final session = await _sessionRepository.findById(sessionId);
    if (session == null) {
      throw UnknownCashEntityViolation(
        entityName: 'CashSession',
        id: sessionId,
      );
    }
    if (session.status != CashSessionStatus.active) {
      throw CashSessionNotActiveViolation(
        sessionId: sessionId,
        statusName: session.status.name,
      );
    }

    final original = await _movementRepository.findById(movementId);
    if (original == null || original.sessionId != sessionId) {
      throw UnknownCashEntityViolation(
        entityName: 'CashMovement',
        id: movementId,
      );
    }

    final now = _clock.now();
    final reversal = CashMovement(
      id: _idGenerator.nextMovementId(),
      sessionId: sessionId,
      drawerId: session.drawerId,
      type: CashMovementType.correction,
      amount: -original.amount,
      reason: reason,
      actorStaffId: actorStaffId,
      timestamp: now,
      reversalOfMovementId: original.id,
    );
    await _movementRepository.append(reversal);

    await _auditRepository.appendEvent(CashAuditEntry(
      id: '${reversal.id}-audit',
      drawerId: session.drawerId,
      sessionId: sessionId,
      type: CashAuditEventType.movementReversed,
      description: 'Reversed movement $movementId: $reason',
      actorStaffId: actorStaffId,
      timestamp: now,
      previousValue: original.id,
      newValue: reversal.id,
    ));

    return reversal;
  }
}
