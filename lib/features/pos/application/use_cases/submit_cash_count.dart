import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../data/cash_audit_entry_repository.dart';
import '../../data/cash_count_repository.dart';
import '../../data/cash_movement_repository.dart';
import '../../data/cash_session_repository.dart';
import '../../domain/cash/cash_audit_entry.dart';
import '../../domain/cash/cash_audit_event_type.dart';
import '../../domain/cash/cash_count.dart';
import '../../domain/cash/cash_declaration.dart';
import '../../domain/cash/cash_session_status.dart';
import '../../domain/cash/cash_variance.dart';
import '../identity/cash_count_id_generator.dart';

/// Submits a new [CashCount] for an active [CashSession] — the
/// "Cash Movements → Cash Count" lifecycle transition. [expectedAmount]
/// is computed here, once, as the sum of every `CashMovement` recorded
/// for the session so far (the opening float is itself the session's
/// first movement, so no separate addition is needed for it) — frozen
/// onto the resulting [CashCount] so a later movement can never
/// retroactively change what an already-submitted count's expected
/// figure was.
///
/// Transitions the session `active -> pendingApproval`
/// (`CashSessionStatusTransitions`). **Never overwrites a previous
/// count** — every call appends a brand-new [CashCount], even a recount
/// after a rejection.
///
/// Throws [CashSessionNotActiveViolation] if the session isn't
/// [CashSessionStatus.active].
class SubmitCashCount {
  const SubmitCashCount({
    required Clock clock,
    required CashCountIdGenerator idGenerator,
    required CashSessionRepository sessionRepository,
    required CashMovementRepository movementRepository,
    required CashCountRepository countRepository,
    required CashAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _sessionRepository = sessionRepository,
        _movementRepository = movementRepository,
        _countRepository = countRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final CashCountIdGenerator _idGenerator;
  final CashSessionRepository _sessionRepository;
  final CashMovementRepository _movementRepository;
  final CashCountRepository _countRepository;
  final CashAuditEntryRepository _auditRepository;

  Future<CashCount> call({
    required String sessionId,
    required Money actualAmount,
    String notes = '',
    required String declaredByStaffId,
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

    final movements = await _movementRepository.findBySessionId(sessionId);
    final expectedAmount = movements.fold<Money>(
      Money.zero(Currency.accountingCurrency),
      (sum, movement) => sum + movement.amount,
    );

    final now = _clock.now();
    final count = CashCount(
      id: _idGenerator.nextCountId(),
      sessionId: sessionId,
      expectedAmount: expectedAmount,
      declaration: CashDeclaration(actualAmount: actualAmount, notes: notes),
      variance: CashVariance.compute(
        expectedAmount: expectedAmount,
        actualAmount: actualAmount,
      ),
      declaredByStaffId: declaredByStaffId,
      declaredAt: now,
    );
    await _countRepository.append(count);

    await _sessionRepository.save(session.copyWith(
      status: CashSessionStatus.pendingApproval,
      revision: session.revision + 1,
    ));

    await _auditRepository.appendEvent(CashAuditEntry(
      id: '${count.id}-audit',
      drawerId: session.drawerId,
      sessionId: sessionId,
      type: CashAuditEventType.countSubmitted,
      description: 'Cash count submitted: variance ${count.variance.type.name}',
      actorStaffId: declaredByStaffId,
      timestamp: now,
      newValue: count.id,
    ));

    return count;
  }
}
