import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../qr/data/table_session_repository.dart';
import '../../../restaurant/data/restaurant_operations_audit_entry_repository.dart';
import '../../../restaurant/domain/audit/restaurant_operations_audit_entry.dart';
import '../../../restaurant/domain/audit/restaurant_operations_audit_event_type.dart';
import '../../data/check_repository.dart';
import '../../domain/authorization/pos_authorization_policy.dart';
import '../../domain/authorization/pos_authorized_action.dart';
import '../../domain/models/check.dart';
import '../../domain/models/check_status.dart';

/// Moves a whole [Check] from its current [TableSession] to a different
/// one — e.g. a party physically moves tables. Never splits or merges
/// items; see `SplitCheckByItem`/`MergeChecks` for that (pre-submission
/// only, Phase 3 Sprint 3D scope — see `docs/decisions.md` ADR-013).
///
/// A still-open (pre-submission) check transfers freely — it's just a
/// metadata move. A [CheckStatus.submitted] check (payment activity may
/// already exist against it) requires
/// [PosAuthorizedAction.transferOrMergeAfterPayment] to be granted first —
/// per the user's explicit instruction that transfer/merge *after payment
/// activity* is one of the actions requiring authorization.
///
/// Throws [UnknownRestaurantOperationsEntityViolation] if the check or
/// either table session doesn't resolve, [AuthorizationDeniedViolation] if
/// a required authorization check is denied.
class TransferCheck {
  const TransferCheck({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CheckRepository checkRepository,
    required TableSessionRepository tableSessionRepository,
    required RestaurantOperationsAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _checkRepository = checkRepository,
        _tableSessionRepository = tableSessionRepository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CheckRepository _checkRepository;
  final TableSessionRepository _tableSessionRepository;
  final RestaurantOperationsAuditEntryRepository _auditRepository;

  Future<Check> call({
    required String checkId,
    required String targetTableSessionId,
    required String performedByStaffId,
  }) async {
    final check = await _checkRepository.findById(checkId);
    if (check == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'Check',
        id: checkId,
      );
    }

    if (check.status == CheckStatus.submitted) {
      final authResult = await _authorizationPolicy.authorize(
        action: PosAuthorizedAction.transferOrMergeAfterPayment,
        actorStaffId: performedByStaffId,
        context: {'checkId': checkId},
      );
      if (!authResult.granted) {
        throw AuthorizationDeniedViolation(
          actionName: PosAuthorizedAction.transferOrMergeAfterPayment.name,
        );
      }
    }

    final sourceTableSession =
        await _tableSessionRepository.findById(check.tableSessionId);
    final targetTableSession =
        await _tableSessionRepository.findById(targetTableSessionId);
    if (sourceTableSession == null || targetTableSession == null) {
      throw UnknownRestaurantOperationsEntityViolation(
        entityName: 'TableSession',
        id: sourceTableSession == null
            ? check.tableSessionId
            : targetTableSessionId,
      );
    }

    final updated = check.copyWith(
      tableSessionId: targetTableSessionId,
      revision: check.revision + 1,
    );
    await _checkRepository.save(updated);
    await _tableSessionRepository
        .save(sourceTableSession.withCheckRemoved(checkId));
    await _tableSessionRepository
        .save(targetTableSession.withCheckAdded(checkId));

    await _auditRepository.appendEvent(
      RestaurantOperationsAuditEntry(
        id: '$checkId-transfer-${updated.revision}',
        branchId: check.branchId,
        type: RestaurantOperationsAuditEventType.checkTransferred,
        description:
            'Check $checkId transferred from ${sourceTableSession.id} to $targetTableSessionId',
        actorStaffId: performedByStaffId,
        timestamp: _clock.now(),
        previousValue: sourceTableSession.id,
        newValue: targetTableSessionId,
      ),
    );

    return updated;
  }
}
