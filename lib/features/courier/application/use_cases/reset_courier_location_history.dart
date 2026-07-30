import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../identity/courier_location_audit_action_id_generator.dart';

/// A manager-authorized request to reset a courier's location tracking
/// baseline — Sprint 5B Part 11's "location reset," one of the actions
/// that must always be audited.
///
/// **Never deletes or mutates any `CourierLocationSnapshot`** — "location
/// history immutable" holds structurally (`CourierLocationRepository` has
/// no update/delete method at all), so this use case cannot violate it
/// even in principle. What it actually does is authorize and audit the
/// *request*; making the courier's device act on it (restarting its
/// `BackgroundLocationSession` to establish a fresh baseline) is
/// presentation/runtime-orchestration wiring not built this sprint — the
/// same category of gap already flagged for the live background-tracking
/// loop itself (see `GeolocatorBackgroundLocationSession`'s doc comment).
class ResetCourierLocationHistory {
  const ResetCourierLocationHistory({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required CourierLocationAuditActionIdGenerator idGenerator,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final CourierLocationAuditActionIdGenerator _idGenerator;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<void> call({
    required String branchId,
    required String courierId,
    required String reason,
    required String performedByStaffId,
  }) async {
    if (reason.trim().isEmpty) {
      throw const ManualOverrideReasonRequiredViolation();
    }

    const action = PosAuthorizedAction.resetCourierLocationHistory;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'courierId': courierId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final actionId = _idGenerator.nextActionId();
    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: actionId,
      branchId: branchId,
      actorStaffId: performedByStaffId,
      courierId: courierId,
      type: CourierAuditEventType.locationHistoryReset,
      description: 'Location tracking reset requested: $reason',
      reason: reason,
      timestamp: now,
      correlationId: actionId,
    ));
  }
}
