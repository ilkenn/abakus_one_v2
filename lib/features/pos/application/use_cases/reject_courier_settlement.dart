import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/courier_cash_declaration_repository.dart';
import '../../data/courier_settlement_audit_entry_repository.dart';
import '../../data/courier_settlement_repository.dart';
import '../../data/courier_settlement_session_repository.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/courier_settlement/courier_settlement.dart';
import '../../domain/courier_settlement/courier_settlement_audit_entry.dart';
import '../../domain/courier_settlement/courier_settlement_audit_event_type.dart';
import '../../domain/courier_settlement/courier_settlement_session_status.dart';
import '../../domain/courier_settlement/courier_settlement_status.dart';
import '../identity/courier_settlement_id_generator.dart';

/// Rejects the latest [CourierCashDeclaration] submitted for a
/// [CourierSettlementSession] — "Manager Review -> Reject" — and
/// transitions the session `pendingApproval -> rejected`. A rejected
/// session returns to declaring only via a fresh
/// `SubmitCourierCashDeclaration` call, mirroring
/// `RejectCashReconciliation` exactly. **No `CashMovement` is ever
/// recorded on rejection** — cash only moves into the drawer once a
/// settlement is actually approved.
///
/// Requires [PosAuthorizedAction.reviewCourierSettlement]. A courier
/// cannot reject/approve their own declaration — throws
/// [SelfApprovalNotAllowedViolation] otherwise. The rejected
/// [CourierSettlement] and the [CourierCashDeclaration] it reviewed both
/// remain in their append-only repositories exactly as recorded.
class RejectCourierSettlement {
  const RejectCourierSettlement({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CourierSettlementIdGenerator idGenerator,
    required CourierSettlementSessionRepository sessionRepository,
    required CourierCashDeclarationRepository declarationRepository,
    required CourierSettlementRepository settlementRepository,
    required CourierSettlementAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _sessionRepository = sessionRepository,
        _declarationRepository = declarationRepository,
        _settlementRepository = settlementRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CourierSettlementIdGenerator _idGenerator;
  final CourierSettlementSessionRepository _sessionRepository;
  final CourierCashDeclarationRepository _declarationRepository;
  final CourierSettlementRepository _settlementRepository;
  final CourierSettlementAuditEntryRepository _auditRepository;

  Future<CourierSettlement> call({
    required String settlementSessionId,
    required String reviewedByStaffId,
    required String managerNotes,
  }) async {
    final session = await _sessionRepository.findById(settlementSessionId);
    if (session == null) {
      throw UnknownCourierSettlementEntityViolation(
        entityName: 'CourierSettlementSession',
        id: settlementSessionId,
      );
    }
    if (session.status != CourierSettlementSessionStatus.pendingApproval) {
      throw InvalidCourierSettlementSessionTransitionViolation(
        fromStatusName: session.status.name,
        toStatusName: CourierSettlementSessionStatus.rejected.name,
      );
    }

    final declaration = await _declarationRepository
        .findLatestBySettlementSessionId(settlementSessionId);
    if (declaration == null) {
      throw UnknownCourierSettlementEntityViolation(
        entityName: 'CourierCashDeclaration',
        id: settlementSessionId,
      );
    }
    if (reviewedByStaffId == declaration.courierId) {
      throw SelfApprovalNotAllowedViolation(staffId: reviewedByStaffId);
    }

    final authResult = await _authorizationPolicy.authorize(
      action: PosAuthorizedAction.reviewCourierSettlement,
      actorStaffId: reviewedByStaffId,
      context: {
        'settlementSessionId': settlementSessionId,
        'decision': 'reject'
      },
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(
        actionName: PosAuthorizedAction.reviewCourierSettlement.name,
      );
    }

    final now = _clock.now();
    final settlement = CourierSettlement(
      id: _idGenerator.nextSettlementId(),
      settlementSessionId: settlementSessionId,
      declarationId: declaration.id,
      status: CourierSettlementStatus.rejected,
      reviewedByStaffId: reviewedByStaffId,
      reviewedAt: now,
      managerNotes: managerNotes,
      variance: declaration.variance,
    );
    await _settlementRepository.append(settlement);

    await _sessionRepository.save(session.copyWith(
      status: CourierSettlementSessionStatus.rejected,
      revision: session.revision + 1,
    ));

    await _auditRepository.appendEvent(CourierSettlementAuditEntry(
      id: '${settlement.id}-audit',
      courierId: session.courierId,
      settlementSessionId: settlementSessionId,
      type: CourierSettlementAuditEventType.approvalRejected,
      description: 'Courier settlement rejected: $managerNotes',
      actorStaffId: reviewedByStaffId,
      timestamp: now,
      newValue: settlement.id,
    ));

    if (!declaration.variance.isExact) {
      await _auditRepository.appendEvent(CourierSettlementAuditEntry(
        id: '${settlement.id}-audit-variance',
        courierId: session.courierId,
        settlementSessionId: settlementSessionId,
        type: CourierSettlementAuditEventType.varianceRejected,
        description: 'Variance not accepted: ${declaration.variance.type.name} '
            '${declaration.variance.amount.minorUnits}',
        actorStaffId: reviewedByStaffId,
        timestamp: now,
      ));
    }

    return settlement;
  }
}
