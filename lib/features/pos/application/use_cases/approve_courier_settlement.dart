import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/courier_cash_declaration_repository.dart';
import '../../data/courier_settlement_audit_entry_repository.dart';
import '../../data/courier_settlement_repository.dart';
import '../../data/courier_settlement_session_repository.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/cash/cash_movement_type.dart';
import '../../domain/courier_settlement/courier_settlement.dart';
import '../../domain/courier_settlement/courier_settlement_audit_entry.dart';
import '../../domain/courier_settlement/courier_settlement_audit_event_type.dart';
import '../../domain/courier_settlement/courier_settlement_session_status.dart';
import '../../domain/courier_settlement/courier_settlement_status.dart';
import '../identity/courier_settlement_id_generator.dart';
import 'record_cash_movement.dart';

/// Approves the latest [CourierCashDeclaration] submitted for a
/// [CourierSettlementSession] — "Manager Review -> Approve" — and
/// transitions the session `pendingApproval -> approved`.
///
/// Requires [PosAuthorizedAction.reviewCourierSettlement]. **A courier can
/// never approve their own settlement**: throws
/// [SelfApprovalNotAllowedViolation] if [reviewedByStaffId] equals the
/// declaration's own [CourierCashDeclaration.courierId], checked before
/// the authorization call — the same structural rule
/// `ApproveCashReconciliation` enforces for cash counts.
///
/// **Cash integration (Phase 3 Sprint 3F <-> Sprint 3E)**: approval
/// automatically records a [CashMovementType.courierCashSettlement]
/// [CashMovement] against [targetCashSessionId] — the cash the courier is
/// physically handing over to that drawer — by calling the existing
/// `RecordCashMovement` unchanged, never a bespoke second financial-event
/// path. The movement's amount is the courier's *declared* amount (what
/// is physically entering the drawer), not the expected figure. No
/// `PaymentSession` is read or written here at all.
class ApproveCourierSettlement {
  const ApproveCourierSettlement({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CourierSettlementIdGenerator idGenerator,
    required CourierSettlementSessionRepository sessionRepository,
    required CourierCashDeclarationRepository declarationRepository,
    required CourierSettlementRepository settlementRepository,
    required CourierSettlementAuditEntryRepository auditRepository,
    required RecordCashMovement recordCashMovement,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _sessionRepository = sessionRepository,
        _declarationRepository = declarationRepository,
        _settlementRepository = settlementRepository,
        _auditRepository = auditRepository,
        _recordCashMovement = recordCashMovement;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CourierSettlementIdGenerator _idGenerator;
  final CourierSettlementSessionRepository _sessionRepository;
  final CourierCashDeclarationRepository _declarationRepository;
  final CourierSettlementRepository _settlementRepository;
  final CourierSettlementAuditEntryRepository _auditRepository;
  final RecordCashMovement _recordCashMovement;

  Future<CourierSettlement> call({
    required String settlementSessionId,
    required String reviewedByStaffId,
    required String targetCashSessionId,
    String managerNotes = '',
    bool varianceAccepted = false,
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
        toStatusName: CourierSettlementSessionStatus.approved.name,
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
        'decision': 'approve'
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
      status: CourierSettlementStatus.approved,
      reviewedByStaffId: reviewedByStaffId,
      reviewedAt: now,
      managerNotes: managerNotes,
      varianceAccepted: varianceAccepted,
      variance: declaration.variance,
    );
    await _settlementRepository.append(settlement);

    await _sessionRepository.save(session.copyWith(
      status: CourierSettlementSessionStatus.approved,
      revision: session.revision + 1,
    ));

    await _recordCashMovement(
      sessionId: targetCashSessionId,
      type: CashMovementType.courierCashSettlement,
      amount: declaration.declaredAmount,
      reason: 'Courier settlement handover: courier "${session.courierId}", '
          'settlement "${settlement.id}"',
      actorStaffId: reviewedByStaffId,
      settlementId: settlement.id,
    );

    await _auditRepository.appendEvent(CourierSettlementAuditEntry(
      id: '${settlement.id}-audit',
      courierId: session.courierId,
      settlementSessionId: settlementSessionId,
      type: CourierSettlementAuditEventType.approvalGranted,
      description: 'Courier settlement approved: $managerNotes',
      actorStaffId: reviewedByStaffId,
      timestamp: now,
      newValue: settlement.id,
    ));

    if (!declaration.variance.isExact && varianceAccepted) {
      await _auditRepository.appendEvent(CourierSettlementAuditEntry(
        id: '${settlement.id}-audit-variance',
        courierId: session.courierId,
        settlementSessionId: settlementSessionId,
        type: CourierSettlementAuditEventType.varianceAccepted,
        description: 'Variance accepted: ${declaration.variance.type.name} '
            '${declaration.variance.amount.minorUnits}',
        actorStaffId: reviewedByStaffId,
        timestamp: now,
      ));
    }

    return settlement;
  }
}
