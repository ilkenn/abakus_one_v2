import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../../shared/models/money.dart';
import '../../data/cash_adjustment_repository.dart';
import '../../data/cash_audit_entry_repository.dart';
import '../../data/cash_movement_repository.dart';
import '../../data/cash_session_repository.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/cash/cash_adjustment.dart';
import '../../domain/cash/cash_audit_entry.dart';
import '../../domain/cash/cash_audit_event_type.dart';
import '../../domain/cash/cash_movement.dart';
import '../../domain/cash/cash_movement_type.dart';
import '../../domain/cash/cash_session_status.dart';
import '../identity/cash_adjustment_id_generator.dart';
import '../identity/cash_movement_id_generator.dart';

/// Records a manager-approved manual correction against an active
/// [CashSession] — produces exactly one [CashMovement]
/// (`CashMovementType.correction`, signed [amount]) plus one linked
/// [CashAdjustment] recording who requested and who approved it.
///
/// [approvedByStaffId] must never equal [requestedByStaffId]
/// (structurally checked before the authorization call, same rule
/// `ApproveCashReconciliation` enforces) — throws
/// [SelfApprovalNotAllowedViolation] otherwise. Requires
/// [PosAuthorizedAction.recordCashAdjustment].
class RecordCashAdjustment {
  const RecordCashAdjustment({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CashAdjustmentIdGenerator adjustmentIdGenerator,
    required CashMovementIdGenerator movementIdGenerator,
    required CashSessionRepository sessionRepository,
    required CashMovementRepository movementRepository,
    required CashAdjustmentRepository adjustmentRepository,
    required CashAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _adjustmentIdGenerator = adjustmentIdGenerator,
        _movementIdGenerator = movementIdGenerator,
        _sessionRepository = sessionRepository,
        _movementRepository = movementRepository,
        _adjustmentRepository = adjustmentRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CashAdjustmentIdGenerator _adjustmentIdGenerator;
  final CashMovementIdGenerator _movementIdGenerator;
  final CashSessionRepository _sessionRepository;
  final CashMovementRepository _movementRepository;
  final CashAdjustmentRepository _adjustmentRepository;
  final CashAuditEntryRepository _auditRepository;

  Future<CashAdjustment> call({
    required String sessionId,
    required Money amount,
    required String reason,
    required String requestedByStaffId,
    required String approvedByStaffId,
  }) async {
    if (requestedByStaffId == approvedByStaffId) {
      throw SelfApprovalNotAllowedViolation(staffId: approvedByStaffId);
    }

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

    final authResult = await _authorizationPolicy.authorize(
      action: PosAuthorizedAction.recordCashAdjustment,
      actorStaffId: approvedByStaffId,
      context: {'sessionId': sessionId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(
        actionName: PosAuthorizedAction.recordCashAdjustment.name,
      );
    }

    final now = _clock.now();
    final movement = CashMovement(
      id: _movementIdGenerator.nextMovementId(),
      sessionId: sessionId,
      drawerId: session.drawerId,
      type: CashMovementType.correction,
      amount: amount,
      reason: reason,
      actorStaffId: approvedByStaffId,
      timestamp: now,
    );
    await _movementRepository.append(movement);

    final adjustment = CashAdjustment(
      id: _adjustmentIdGenerator.nextAdjustmentId(),
      sessionId: sessionId,
      movementId: movement.id,
      reason: reason,
      requestedByStaffId: requestedByStaffId,
      approvedByStaffId: approvedByStaffId,
      createdAt: now,
    );
    await _adjustmentRepository.append(adjustment);

    await _auditRepository.appendEvent(CashAuditEntry(
      id: '${adjustment.id}-audit',
      drawerId: session.drawerId,
      sessionId: sessionId,
      type: CashAuditEventType.manualAdjustment,
      description: 'Manual adjustment: $reason',
      actorStaffId: approvedByStaffId,
      timestamp: now,
      newValue: movement.id,
    ));

    return adjustment;
  }
}
