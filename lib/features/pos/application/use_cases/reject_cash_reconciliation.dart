import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/cash_audit_entry_repository.dart';
import '../../data/cash_count_repository.dart';
import '../../data/cash_reconciliation_repository.dart';
import '../../data/cash_session_repository.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/cash/cash_audit_entry.dart';
import '../../domain/cash/cash_audit_event_type.dart';
import '../../domain/cash/cash_reconciliation.dart';
import '../../domain/cash/cash_session_status.dart';
import '../identity/cash_reconciliation_id_generator.dart';

/// Rejects the latest [CashCount] submitted for a [CashSession] —
/// "Manager Review → Reject" — and transitions the session
/// `pendingApproval -> rejected`. A rejected session returns to `active`
/// only via a fresh count submission (`SubmitCashCount`), which is itself
/// what moves it out of `rejected` (`CashSessionStatusTransitions`).
///
/// Requires [PosAuthorizedAction.reviewCashReconciliation]. A cashier
/// cannot reject/approve their own count, same rule as
/// `ApproveCashReconciliation` enforces — throws
/// [SelfApprovalNotAllowedViolation] otherwise. The rejected
/// [CashReconciliation] and the [CashCount] it reviewed both remain in
/// their append-only repositories exactly as recorded — nothing here
/// deletes or edits either.
class RejectCashReconciliation {
  const RejectCashReconciliation({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CashReconciliationIdGenerator idGenerator,
    required CashSessionRepository sessionRepository,
    required CashCountRepository countRepository,
    required CashReconciliationRepository reconciliationRepository,
    required CashAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _sessionRepository = sessionRepository,
        _countRepository = countRepository,
        _reconciliationRepository = reconciliationRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CashReconciliationIdGenerator _idGenerator;
  final CashSessionRepository _sessionRepository;
  final CashCountRepository _countRepository;
  final CashReconciliationRepository _reconciliationRepository;
  final CashAuditEntryRepository _auditRepository;

  Future<CashReconciliation> call({
    required String sessionId,
    required String reviewedByStaffId,
    required String managerComments,
  }) async {
    final session = await _sessionRepository.findById(sessionId);
    if (session == null) {
      throw UnknownCashEntityViolation(
        entityName: 'CashSession',
        id: sessionId,
      );
    }
    if (session.status != CashSessionStatus.pendingApproval) {
      throw InvalidCashSessionTransitionViolation(
        fromStatusName: session.status.name,
        toStatusName: CashSessionStatus.rejected.name,
      );
    }

    final count = await _countRepository.findLatestBySessionId(sessionId);
    if (count == null) {
      throw UnknownCashEntityViolation(
        entityName: 'CashCount',
        id: sessionId,
      );
    }
    if (reviewedByStaffId == count.declaredByStaffId) {
      throw SelfApprovalNotAllowedViolation(staffId: reviewedByStaffId);
    }

    final authResult = await _authorizationPolicy.authorize(
      action: PosAuthorizedAction.reviewCashReconciliation,
      actorStaffId: reviewedByStaffId,
      context: {'sessionId': sessionId, 'decision': 'reject'},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(
        actionName: PosAuthorizedAction.reviewCashReconciliation.name,
      );
    }

    final now = _clock.now();
    final reconciliation = CashReconciliation(
      id: _idGenerator.nextReconciliationId(),
      sessionId: sessionId,
      cashCountId: count.id,
      status: CashReconciliationStatus.rejected,
      reviewedByStaffId: reviewedByStaffId,
      reviewedAt: now,
      managerComments: managerComments,
      variance: count.variance,
    );
    await _reconciliationRepository.append(reconciliation);

    await _sessionRepository.save(session.copyWith(
      status: CashSessionStatus.rejected,
      revision: session.revision + 1,
    ));

    await _auditRepository.appendEvent(CashAuditEntry(
      id: '${reconciliation.id}-audit',
      drawerId: session.drawerId,
      sessionId: sessionId,
      type: CashAuditEventType.approvalRejected,
      description: 'Cash reconciliation rejected: $managerComments',
      actorStaffId: reviewedByStaffId,
      timestamp: now,
      newValue: reconciliation.id,
    ));

    return reconciliation;
  }
}
