import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/location_emergency_override_repository.dart';
import '../../domain/audit/courier_audit_event_type.dart';
import '../../domain/audit/courier_operational_audit_entry.dart';
import '../../domain/location/location_emergency_override.dart';
import '../identity/location_emergency_override_id_generator.dart';

/// A manager grants a courier the ability to keep progressing an
/// operational action while their location is reported unavailable —
/// "manager override must require authorization, reason, timestamp, and
/// audit evidence." Requires a non-empty [reason] (reuses
/// `ManualOverrideReasonRequiredViolation`, the same violation
/// `ManuallyAssignDelivery`/`OverrideGeofence` already use for the
/// identical rule). Immutable once granted — no update/delete method
/// exists on `LocationEmergencyOverrideRepository`.
class GrantLocationEmergencyOverride {
  const GrantLocationEmergencyOverride({
    required Clock clock,
    required PosAuthorizationPolicy authorizationPolicy,
    required LocationEmergencyOverrideIdGenerator idGenerator,
    required LocationEmergencyOverrideRepository repository,
    required CourierOperationalAuditEntryRepository auditRepository,
  })  : _clock = clock,
        _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final Clock _clock;
  final PosAuthorizationPolicy _authorizationPolicy;
  final LocationEmergencyOverrideIdGenerator _idGenerator;
  final LocationEmergencyOverrideRepository _repository;
  final CourierOperationalAuditEntryRepository _auditRepository;

  Future<LocationEmergencyOverride> call({
    required String courierId,
    required String branchId,
    String? deliveryId,
    required String reason,
    DateTime? expiresAt,
    required String authorizedByStaffId,
  }) async {
    if (reason.trim().isEmpty) {
      throw const ManualOverrideReasonRequiredViolation();
    }

    const action = PosAuthorizedAction.grantLocationEmergencyOverride;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: authorizedByStaffId,
      context: {'courierId': courierId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final now = _clock.now();
    final override = LocationEmergencyOverride(
      id: _idGenerator.nextOverrideId(),
      courierId: courierId,
      deliveryId: deliveryId,
      reason: reason,
      authorizedByStaffId: authorizedByStaffId,
      grantedAt: now,
      expiresAt: expiresAt,
    );
    await _repository.append(override);

    await _auditRepository.appendEvent(CourierOperationalAuditEntry(
      id: '${override.id}-audit',
      branchId: branchId,
      actorStaffId: authorizedByStaffId,
      courierId: courierId,
      deliveryId: deliveryId,
      type: CourierAuditEventType.locationEmergencyOverrideGranted,
      description: 'Location emergency override granted: $reason',
      reason: reason,
      timestamp: now,
      correlationId: override.id,
    ));

    return override;
  }
}
