import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../../shared/models/money.dart';
import '../../data/cash_audit_entry_repository.dart';
import '../../data/cash_movement_repository.dart';
import '../../data/cash_session_repository.dart';
import '../../domain/cash/cash_audit_entry.dart';
import '../../domain/cash/cash_audit_event_type.dart';
import '../../domain/cash/cash_movement.dart';
import '../../domain/cash/cash_movement_type.dart';
import '../../domain/cash/cash_session_status.dart';
import '../identity/cash_movement_id_generator.dart';

/// Records a new [CashMovement] against an active [CashSession].
///
/// [amount] is a **non-negative magnitude** for every [CashMovementType]
/// except `correction`/`closingDifference` (`CashMovementType.isInflow ==
/// null`), for which [amount] is used exactly as given — those two types
/// are the only ones whose direction the caller controls (see
/// `ReverseCashMovement`/`RecordCashAdjustment`). For every other type,
/// the sign is derived from [CashMovementType.isInflow] and a negative
/// [amount] is rejected outright — a caller cannot record a `cashSale` as
/// a shortfall by mistake.
///
/// Throws [CashSessionNotActiveViolation] if the session isn't
/// [CashSessionStatus.active] — once counting/approval has begun, no
/// further movement may be recorded against that session.
class RecordCashMovement {
  const RecordCashMovement({
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
    required CashMovementType type,
    required Money amount,
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

    final direction = type.isInflow;
    Money signedAmount;
    if (direction == null) {
      signedAmount = amount;
    } else {
      if (amount.isNegative) {
        throw NegativeAmountViolation(
          context: 'RecordCashMovement.amount',
          minorUnits: amount.minorUnits,
          currencyCode: amount.currency.isoCode,
        );
      }
      signedAmount = direction ? amount : -amount;
    }

    final now = _clock.now();
    final movement = CashMovement(
      id: _idGenerator.nextMovementId(),
      sessionId: sessionId,
      drawerId: session.drawerId,
      type: type,
      amount: signedAmount,
      reason: reason,
      actorStaffId: actorStaffId,
      timestamp: now,
    );
    await _movementRepository.append(movement);

    await _auditRepository.appendEvent(CashAuditEntry(
      id: '${movement.id}-audit',
      drawerId: session.drawerId,
      sessionId: sessionId,
      type: CashAuditEventType.movementAdded,
      description: '${type.name}: $reason',
      actorStaffId: actorStaffId,
      timestamp: now,
      newValue: signedAmount.minorUnits.toString(),
    ));

    return movement;
  }
}
