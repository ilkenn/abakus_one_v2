import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/courier_shift_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/events/courier_event_type.dart';
import '../../domain/shift/courier_shift.dart';
import '../../domain/shift/courier_shift_status.dart';
import 'record_courier_event.dart';

/// Approves or rejects a courier's shift request — "manager approval is
/// required before the shift becomes active," and "courier cannot approve
/// their own shift": throws [SelfApprovalNotAllowedViolation] (reused
/// directly from Sprint 3E/3F/Phase 4 — the exact same generic violation)
/// if [reviewedByStaffId] equals [CourierShift.courierId], checked before
/// the authorization call.
class ReviewCourierShift {
  const ReviewCourierShift({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CourierShiftRepository repository,
    required CourierOperationalAuditEntryRepository auditRepository,
    required RecordCourierEvent recordCourierEvent,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository,
        _recordCourierEvent = recordCourierEvent;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CourierShiftRepository _repository;
  final CourierOperationalAuditEntryRepository _auditRepository;
  final RecordCourierEvent _recordCourierEvent;

  Future<CourierShift> call({
    required String shiftId,
    required bool approve,
    required String reviewedByStaffId,
    String? rejectionReason,
  }) async {
    final shift = await _repository.findById(shiftId);
    if (shift == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'CourierShift',
        id: shiftId,
      );
    }
    if (shift.status != CourierShiftStatus.awaitingManagerApproval) {
      throw InvalidCourierShiftTransitionViolation(
        fromStatusName: shift.status.name,
        toStatusName: approve
            ? CourierShiftStatus.approved.name
            : CourierShiftStatus.rejected.name,
      );
    }
    if (reviewedByStaffId == shift.courierId) {
      throw SelfApprovalNotAllowedViolation(staffId: reviewedByStaffId);
    }

    const action = PosAuthorizedAction.reviewCourierShift;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: reviewedByStaffId,
      context: {'shiftId': shiftId, 'decision': approve ? 'approve' : 'reject'},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final newStatus =
        approve ? CourierShiftStatus.approved : CourierShiftStatus.rejected;
    final updated = shift.copyWith(
      status: newStatus,
      approvedByStaffId: approve ? reviewedByStaffId : null,
      approvedAt: approve ? now : null,
      rejectionReason: approve ? null : rejectionReason,
      revision: shift.revision + 1,
    );
    await _repository.save(updated);

    final event = await _recordCourierEvent(
      branchId: shift.branchId,
      courierId: shift.courierId,
      shiftId: shift.id,
      type: approve
          ? CourierEventType.shiftApproved
          : CourierEventType.shiftRejected,
      idempotencyKey: '${shift.id}-rev${updated.revision}',
      occurredAt: now,
    );

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${event.id}-audit',
      branchId: shift.branchId,
      actorStaffId: reviewedByStaffId,
      courierId: shift.courierId,
      shiftId: shift.id,
      type: approve
          ? CourierAuditEventType.shiftApproved
          : CourierAuditEventType.shiftRejected,
      description:
          approve ? 'Shift approved' : 'Shift rejected: $rejectionReason',
      previousStateName: shift.status.name,
      newStateName: newStatus.name,
      reason: rejectionReason,
      timestamp: now,
      correlationId: event.idempotencyKey,
    ));

    return updated;
  }
}
