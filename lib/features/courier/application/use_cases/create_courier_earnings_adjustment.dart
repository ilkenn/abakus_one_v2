import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../../shared/models/money.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_earnings_adjustment_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/compensation/courier_earnings_adjustment.dart';
import '../../domain/compensation/courier_earnings_adjustment_reason.dart';
import '../identity/courier_earnings_adjustment_id_generator.dart';

/// A manager creates an append-only correction to a courier's earnings —
/// "managers may create append-only adjustments... never modify original
/// earnings." [reason] is one of the predefined
/// [CourierEarningsAdjustmentReason] values — no free-text reason field
/// exists. [amount] may be positive (a top-up) or negative (a deduction).
/// This use case never reads or writes [DeliveryEarnings]/
/// [ShiftHourlyEarnings] at all — structurally impossible to touch them,
/// not just disciplined not to.
class CreateCourierEarningsAdjustment {
  const CreateCourierEarningsAdjustment({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CourierEarningsAdjustmentIdGenerator idGenerator,
    required CourierEarningsAdjustmentRepository repository,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CourierEarningsAdjustmentIdGenerator _idGenerator;
  final CourierEarningsAdjustmentRepository _repository;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<CourierEarningsAdjustment> call({
    required String courierId,
    required String branchId,
    String? relatedShiftId,
    String? relatedDeliveryId,
    required CourierEarningsAdjustmentReason reason,
    required Money amount,
    String notes = '',
    required String performedByStaffId,
  }) async {
    const action = PosAuthorizedAction.createCourierEarningsAdjustment;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'courierId': courierId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final adjustment = CourierEarningsAdjustment(
      id: _idGenerator.nextAdjustmentId(),
      courierId: courierId,
      relatedShiftId: relatedShiftId,
      relatedDeliveryId: relatedDeliveryId,
      reason: reason,
      amount: amount,
      notes: notes,
      actorStaffId: performedByStaffId,
      createdAt: now,
    );
    await _repository.append(adjustment);

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${adjustment.id}-audit',
      branchId: branchId,
      actorStaffId: performedByStaffId,
      courierId: courierId,
      deliveryId: relatedDeliveryId,
      shiftId: relatedShiftId,
      type: CourierAuditEventType.earningsAdjustmentCreated,
      description:
          'Earnings adjustment (${reason.name}): ${amount.minorUnits} minor units',
      reason: notes.isEmpty ? null : notes,
      timestamp: now,
      correlationId: adjustment.id,
    ));

    return adjustment;
  }
}
