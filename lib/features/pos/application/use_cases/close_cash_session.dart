import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/cash_audit_entry_repository.dart';
import '../../data/cash_reconciliation_repository.dart';
import '../../data/cash_session_repository.dart';
import '../../domain/cash/cash_audit_entry.dart';
import '../../domain/cash/cash_audit_event_type.dart';
import '../../domain/cash/cash_closing.dart';
import '../../domain/cash/cash_session.dart';
import '../../domain/cash/cash_session_status.dart';

/// Closes an already-`approved` [CashSession] — "Manager Approval →
/// Close Drawer → Archived" (the drawer itself stays in service; only
/// this specific session ends). **Manager approval is required before
/// closing**: throws [InvalidCashSessionTransitionViolation] if the
/// session isn't [CashSessionStatus.approved] — there is no path from
/// `active`/`pendingApproval`/`rejected` directly to `closed`.
class CloseCashSession {
  const CloseCashSession({
    required Clock clock,
    required CashSessionRepository sessionRepository,
    required CashReconciliationRepository reconciliationRepository,
    required CashAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _sessionRepository = sessionRepository,
        _reconciliationRepository = reconciliationRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final CashSessionRepository _sessionRepository;
  final CashReconciliationRepository _reconciliationRepository;
  final CashAuditEntryRepository _auditRepository;

  Future<CashSession> call({
    required String sessionId,
    required String closedByStaffId,
  }) async {
    final session = await _sessionRepository.findById(sessionId);
    if (session == null) {
      throw UnknownCashEntityViolation(
        entityName: 'CashSession',
        id: sessionId,
      );
    }
    if (session.status != CashSessionStatus.approved) {
      throw InvalidCashSessionTransitionViolation(
        fromStatusName: session.status.name,
        toStatusName: CashSessionStatus.closed.name,
      );
    }

    final reconciliation =
        await _reconciliationRepository.findLatestBySessionId(sessionId);
    if (reconciliation == null) {
      throw UnknownCashEntityViolation(
        entityName: 'CashReconciliation',
        id: sessionId,
      );
    }

    final now = _clock.now();
    final closed = session.copyWith(
      status: CashSessionStatus.closed,
      closing: CashClosing(
        closedByStaffId: closedByStaffId,
        closedAt: now,
        finalCashCountId: reconciliation.cashCountId,
        reconciliationId: reconciliation.id,
      ),
      revision: session.revision + 1,
    );
    await _sessionRepository.save(closed);

    await _auditRepository.appendEvent(CashAuditEntry(
      id: '${session.id}-audit-closed',
      drawerId: session.drawerId,
      sessionId: sessionId,
      type: CashAuditEventType.drawerClosed,
      description: 'Cash session closed',
      actorStaffId: closedByStaffId,
      timestamp: now,
    ));

    return closed;
  }
}
