import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../../shared/models/money.dart';
import '../../data/courier_settlement_adjustment_repository.dart';
import '../../data/courier_settlement_audit_entry_repository.dart';
import '../../data/courier_settlement_session_repository.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/cash/cash_movement_type.dart';
import '../../domain/courier_settlement/courier_settlement_adjustment.dart';
import '../../domain/courier_settlement/courier_settlement_audit_entry.dart';
import '../../domain/courier_settlement/courier_settlement_audit_event_type.dart';
import '../../domain/courier_settlement/courier_settlement_session_status.dart';
import '../identity/courier_settlement_adjustment_id_generator.dart';
import 'record_cash_movement.dart';

/// Records a manager-approved manual correction against a
/// [CourierSettlementSession] — produces exactly one
/// [CashMovementType.correction] `CashMovement` (via the existing
/// `RecordCashMovement`, never a bespoke second path) plus one linked
/// [CourierSettlementAdjustment] recording who requested and who approved
/// it. Mirrors `RecordCashAdjustment` exactly.
///
/// [approvedByStaffId] must never equal [requestedByStaffId] — throws
/// [SelfApprovalNotAllowedViolation] otherwise, checked before the
/// authorization call. Requires
/// [PosAuthorizedAction.recordCourierSettlementAdjustment]. May be
/// recorded any time before the session is [CourierSettlementSessionStatus.closed]
/// — a settlement's variance may need correcting either during manager
/// review or after approval, unlike a POS drawer's `CashAdjustment`
/// (Sprint 3E), which is scoped to an `active` session only; this is a
/// deliberate, documented widening for the courier-settlement case (see
/// `docs/decisions.md` ADR-015).
class RecordCourierSettlementAdjustment {
  const RecordCourierSettlementAdjustment({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CourierSettlementAdjustmentIdGenerator adjustmentIdGenerator,
    required CourierSettlementSessionRepository sessionRepository,
    required CourierSettlementAdjustmentRepository adjustmentRepository,
    required CourierSettlementAuditEntryRepository auditRepository,
    required RecordCashMovement recordCashMovement,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _adjustmentIdGenerator = adjustmentIdGenerator,
        _sessionRepository = sessionRepository,
        _adjustmentRepository = adjustmentRepository,
        _auditRepository = auditRepository,
        _recordCashMovement = recordCashMovement;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CourierSettlementAdjustmentIdGenerator _adjustmentIdGenerator;
  final CourierSettlementSessionRepository _sessionRepository;
  final CourierSettlementAdjustmentRepository _adjustmentRepository;
  final CourierSettlementAuditEntryRepository _auditRepository;
  final RecordCashMovement _recordCashMovement;

  Future<CourierSettlementAdjustment> call({
    required String settlementSessionId,
    required String targetCashSessionId,
    required Money amount,
    required String reason,
    required String requestedByStaffId,
    required String approvedByStaffId,
  }) async {
    if (requestedByStaffId == approvedByStaffId) {
      throw SelfApprovalNotAllowedViolation(staffId: approvedByStaffId);
    }

    final session = await _sessionRepository.findById(settlementSessionId);
    if (session == null) {
      throw UnknownCourierSettlementEntityViolation(
        entityName: 'CourierSettlementSession',
        id: settlementSessionId,
      );
    }
    if (session.status == CourierSettlementSessionStatus.closed) {
      throw CourierSettlementSessionNotActiveViolation(
        sessionId: settlementSessionId,
        statusName: session.status.name,
      );
    }

    final authResult = await _authorizationPolicy.authorize(
      action: PosAuthorizedAction.recordCourierSettlementAdjustment,
      actorStaffId: approvedByStaffId,
      context: {'settlementSessionId': settlementSessionId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(
        actionName: PosAuthorizedAction.recordCourierSettlementAdjustment.name,
      );
    }

    final now = _clock.now();
    final movement = await _recordCashMovement(
      sessionId: targetCashSessionId,
      type: CashMovementType.correction,
      amount: amount,
      reason: reason,
      actorStaffId: approvedByStaffId,
    );

    final adjustment = CourierSettlementAdjustment(
      id: _adjustmentIdGenerator.nextAdjustmentId(),
      settlementSessionId: settlementSessionId,
      movementId: movement.id,
      reason: reason,
      requestedByStaffId: requestedByStaffId,
      approvedByStaffId: approvedByStaffId,
      createdAt: now,
    );
    await _adjustmentRepository.append(adjustment);

    await _auditRepository.appendEvent(CourierSettlementAuditEntry(
      id: '${adjustment.id}-audit',
      courierId: session.courierId,
      settlementSessionId: settlementSessionId,
      type: CourierSettlementAuditEventType.adjustmentRecorded,
      description: 'Manual adjustment: $reason',
      actorStaffId: approvedByStaffId,
      timestamp: now,
      newValue: movement.id,
    ));

    return adjustment;
  }
}
