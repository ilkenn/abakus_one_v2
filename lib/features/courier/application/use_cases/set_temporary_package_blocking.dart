import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/courier_package_blocking_status_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/availability/courier_package_blocking_status.dart';

/// A manager blocks (or unblocks) a courier from receiving *new* package
/// assignments while they finish their existing ones — Sprint 5C Part 7's
/// "temporary package blocking." Manager-only
/// ([PosAuthorizedAction.setTemporaryPackageBlocking]). Never touches
/// `CourierAvailabilityStatus` — the courier stays visibly
/// `available`/`busy` as normal; only `DispatchScorer`'s eligibility
/// check (via `DispatchScoringInput
/// .isTemporarilyBlockedFromNewPackages`) is affected by this record.
class SetTemporaryPackageBlocking {
  const SetTemporaryPackageBlocking({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CourierPackageBlockingStatusRepository repository,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CourierPackageBlockingStatusRepository _repository;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<CourierPackageBlockingStatus> call({
    required String branchId,
    required String courierId,
    required bool isBlocked,
    String? reason,
    required String performedByStaffId,
  }) async {
    const action = PosAuthorizedAction.setTemporaryPackageBlocking;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'courierId': courierId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final previous = await _repository.findByCourierId(courierId);
    final now = _clock.now();
    final updated = CourierPackageBlockingStatus(
      courierId: courierId,
      isBlocked: isBlocked,
      reason: reason,
      setByStaffId: performedByStaffId,
      setAt: now,
      revision: (previous?.revision ?? 0) + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '$courierId-blocking-rev${updated.revision}',
      branchId: branchId,
      actorStaffId: performedByStaffId,
      courierId: courierId,
      type: CourierAuditEventType.temporaryPackageBlockingChanged,
      description: isBlocked
          ? 'Temporary package blocking enabled'
          : 'Temporary package blocking lifted',
      previousStateName: previous?.isBlocked.toString(),
      newStateName: isBlocked.toString(),
      reason: reason,
      timestamp: now,
      correlationId: '$courierId-blocking-rev${updated.revision}',
    ));

    return updated;
  }
}
