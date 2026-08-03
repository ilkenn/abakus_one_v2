import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/entitlement_audit_entry_repository.dart';
import '../../data/entitlement_grant_repository.dart';
import '../../domain/audit/entitlement_audit_entry.dart';
import '../../domain/audit/entitlement_audit_event_type.dart';
import '../../domain/entitlement_grant.dart';
import '../../domain/entitlement_status.dart';

/// Changes an existing [EntitlementGrant]'s [EntitlementStatus] — e.g.
/// `trial -> active` (conversion), `active -> revoked` (cancellation),
/// `active -> expired` — admin-only
/// (`PosAuthorizedAction.manageEntitlements`).
class SetEntitlementStatus {
  const SetEntitlementStatus({
    required PosAuthorizationPolicy authorizationPolicy,
    required EntitlementGrantRepository repository,
    required EntitlementAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final EntitlementGrantRepository _repository;
  final EntitlementAuditEntryRepository _auditRepository;

  Future<EntitlementGrant> call({
    required String grantId,
    required EntitlementStatus newStatus,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageEntitlements;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.findById(grantId);
    if (existing == null) {
      throw UnknownEntitlementGrantViolation(id: grantId);
    }

    final updated = existing.copyWith(
      status: newStatus,
      revision: existing.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(EntitlementAuditEntry(
      id: '$grantId-audit-status-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: newStatus == EntitlementStatus.revoked
          ? EntitlementAuditEventType.entitlementRevoked
          : EntitlementAuditEventType.entitlementStatusChanged,
      description: 'Entitlement status changed to "${newStatus.name}"',
      targetEntityId: grantId,
      previousStateName: existing.status.name,
      newStateName: newStatus.name,
      timestamp: performedAt,
    ));

    return updated;
  }
}
