import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../../shared/models/money.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_earnings_payment_repository.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/compensation/courier_earnings_payment.dart';
import '../identity/courier_earnings_payment_id_generator.dart';

/// Marks a specific set of [DeliveryEarnings]/[ShiftHourlyEarnings]/
/// [CourierEarningsAdjustment] ids as paid — "locked earnings become
/// immutable." Throws [EarningsAlreadyPaidViolation] if any referenced id
/// already appears in an earlier [CourierEarningsPayment] — no id is ever
/// paid twice. Neither referenced record type is mutated by this use
/// case (neither has an update method at all); a future correction is
/// always a brand-new [CourierEarningsAdjustment], never a reopening of
/// this payment.
class MarkCourierEarningsPaid {
  const MarkCourierEarningsPaid({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CourierEarningsPaymentIdGenerator idGenerator,
    required CourierEarningsPaymentRepository repository,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CourierEarningsPaymentIdGenerator _idGenerator;
  final CourierEarningsPaymentRepository _repository;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<CourierEarningsPayment> call({
    required String courierId,
    required String branchId,
    required DateTime periodStart,
    required DateTime periodEnd,
    required Money totalAmount,
    List<String> deliveryEarningsIds = const [],
    List<String> shiftEarningsIds = const [],
    List<String> adjustmentIds = const [],
    required String performedByStaffId,
  }) async {
    for (final id in [
      ...deliveryEarningsIds,
      ...shiftEarningsIds,
      ...adjustmentIds,
    ]) {
      final existingPayments = await _repository.findByReferencedId(id);
      if (existingPayments.isNotEmpty) {
        throw EarningsAlreadyPaidViolation(earningsId: id);
      }
    }

    const action = PosAuthorizedAction.markCourierEarningsPaid;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'courierId': courierId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final payment = CourierEarningsPayment(
      id: _idGenerator.nextPaymentId(),
      courierId: courierId,
      periodStart: periodStart,
      periodEnd: periodEnd,
      totalAmount: totalAmount,
      deliveryEarningsIds: deliveryEarningsIds,
      shiftEarningsIds: shiftEarningsIds,
      adjustmentIds: adjustmentIds,
      paidByStaffId: performedByStaffId,
      paidAt: now,
    );
    await _repository.append(payment);

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${payment.id}-audit',
      branchId: branchId,
      actorStaffId: performedByStaffId,
      courierId: courierId,
      type: CourierAuditEventType.earningsMarkedPaid,
      description:
          'Earnings marked paid: ${totalAmount.minorUnits} minor units '
          '($periodStart - $periodEnd)',
      timestamp: now,
      correlationId: payment.id,
    ));

    return payment;
  }
}
