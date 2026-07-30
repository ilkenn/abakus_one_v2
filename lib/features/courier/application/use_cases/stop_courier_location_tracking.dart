import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/location/background_location_session.dart';
import '../identity/courier_location_audit_action_id_generator.dart';

/// Stops a courier's [BackgroundLocationSession] and records it —
/// Sprint 5B Part 11: "audit every... tracking start/stop." Authorized via
/// [PosAuthorizedAction.stopCourierLocationTracking].
class StopCourierLocationTracking {
  const StopCourierLocationTracking({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required BackgroundLocationSession session,
    required CourierLocationAuditActionIdGenerator idGenerator,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _session = session,
        _idGenerator = idGenerator,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final BackgroundLocationSession _session;
  final CourierLocationAuditActionIdGenerator _idGenerator;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<void> call({
    required String branchId,
    required String courierId,
    required String deviceId,
    required String performedByStaffId,
  }) async {
    const action = PosAuthorizedAction.stopCourierLocationTracking;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {'courierId': courierId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    await _session.stop(courierId: courierId, deviceId: deviceId);

    final now = _clock.now();
    final actionId = _idGenerator.nextActionId();
    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: actionId,
      branchId: branchId,
      actorStaffId: performedByStaffId,
      courierId: courierId,
      deviceId: deviceId,
      type: CourierAuditEventType.locationTrackingStopped,
      description: 'Location tracking stopped',
      timestamp: now,
      correlationId: actionId,
    ));
  }
}
