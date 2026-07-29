import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/courier_settlement_audit_entry_repository.dart';
import '../../data/courier_settlement_session_repository.dart';
import '../../domain/courier_settlement/courier_settlement_audit_entry.dart';
import '../../domain/courier_settlement/courier_settlement_audit_event_type.dart';
import '../../domain/courier_settlement/courier_settlement_session.dart';
import '../../domain/courier_settlement/courier_settlement_session_status.dart';

/// Closes an already-`approved` [CourierSettlementSession] — "Approve ->
/// Settlement Closed". **A courier can never close their own
/// settlement** (Phase 3 Sprint 3F business rule) — this use case takes
/// only [closedByStaffId] (a manager/staff actor), never a courier actor,
/// and requires the session to already be
/// [CourierSettlementSessionStatus.approved]: throws
/// [InvalidCourierSettlementSessionTransitionViolation] otherwise — there
/// is no path from `active`/`pendingApproval`/`rejected` directly to
/// `closed`. Mirrors `CloseCashSession` exactly.
class CloseCourierSettlementSession {
  const CloseCourierSettlementSession({
    required Clock clock,
    required CourierSettlementSessionRepository sessionRepository,
    required CourierSettlementAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _sessionRepository = sessionRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final CourierSettlementSessionRepository _sessionRepository;
  final CourierSettlementAuditEntryRepository _auditRepository;

  Future<CourierSettlementSession> call({
    required String settlementSessionId,
    required String closedByStaffId,
  }) async {
    final session = await _sessionRepository.findById(settlementSessionId);
    if (session == null) {
      throw UnknownCourierSettlementEntityViolation(
        entityName: 'CourierSettlementSession',
        id: settlementSessionId,
      );
    }
    if (session.status != CourierSettlementSessionStatus.approved) {
      throw InvalidCourierSettlementSessionTransitionViolation(
        fromStatusName: session.status.name,
        toStatusName: CourierSettlementSessionStatus.closed.name,
      );
    }

    final now = _clock.now();
    final closed = session.copyWith(
      status: CourierSettlementSessionStatus.closed,
      closedAt: now,
      revision: session.revision + 1,
    );
    await _sessionRepository.save(closed);

    await _auditRepository.appendEvent(CourierSettlementAuditEntry(
      id: '${session.id}-audit-closed',
      courierId: session.courierId,
      settlementSessionId: settlementSessionId,
      type: CourierSettlementAuditEventType.settlementClosed,
      description: 'Courier settlement session closed',
      actorStaffId: closedByStaffId,
      timestamp: now,
    ));

    return closed;
  }
}
