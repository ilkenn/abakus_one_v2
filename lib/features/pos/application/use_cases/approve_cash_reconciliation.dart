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
import '../../domain/cash/cash_variance.dart';
import '../identity/cash_reconciliation_id_generator.dart';

/// Approves the latest [CashCount] submitted for a [CashSession] —
/// "Manager Review → Approve" — and transitions the session
/// `pendingApproval -> approved`.
///
/// Requires [PosAuthorizedAction.reviewCashReconciliation]. **A cashier
/// can never approve their own reconciliation**: throws
/// [SelfApprovalNotAllowedViolation] if [reviewedByStaffId] equals the
/// count's own [CashCount.declaredByStaffId], checked before the
/// authorization call — this is a structural rule, not merely a policy
/// choice a permissive authorization result could override.
///
/// A non-zero [CashVariance] does not by itself block approval — the
/// caller passes [varianceAccepted] explicitly to say so; a manager who
/// does *not* accept the variance should call
/// [RejectCashReconciliation] instead.
class ApproveCashReconciliation {
  const ApproveCashReconciliation({
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
    String managerComments = '',
    bool varianceAccepted = false,
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
        toStatusName: CashSessionStatus.approved.name,
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
      context: {'sessionId': sessionId, 'decision': 'approve'},
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
      status: CashReconciliationStatus.approved,
      reviewedByStaffId: reviewedByStaffId,
      reviewedAt: now,
      managerComments: managerComments,
      varianceAccepted: varianceAccepted,
      variance: count.variance,
    );
    await _reconciliationRepository.append(reconciliation);

    await _sessionRepository.save(session.copyWith(
      status: CashSessionStatus.approved,
      revision: session.revision + 1,
    ));

    await _auditRepository.appendEvent(CashAuditEntry(
      id: '${reconciliation.id}-audit',
      drawerId: session.drawerId,
      sessionId: sessionId,
      type: CashAuditEventType.approvalGranted,
      description: 'Cash reconciliation approved: $managerComments',
      actorStaffId: reviewedByStaffId,
      timestamp: now,
      newValue: reconciliation.id,
    ));

    if (!count.variance.isExact && varianceAccepted) {
      await _auditRepository.appendEvent(CashAuditEntry(
        id: '${reconciliation.id}-audit-variance',
        drawerId: session.drawerId,
        sessionId: sessionId,
        type: CashAuditEventType.varianceAccepted,
        description:
            'Variance accepted: ${count.variance.type.name} ${count.variance.amount.minorUnits}',
        actorStaffId: reviewedByStaffId,
        timestamp: now,
      ));
    }

    return reconciliation;
  }
}
