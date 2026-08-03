import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/entitlement_audit_entry_repository.dart';
import '../../data/entitlement_grant_repository.dart';
import '../../domain/audit/entitlement_audit_entry.dart';
import '../../domain/audit/entitlement_audit_event_type.dart';
import '../../domain/entitlement_grant.dart';
import '../../domain/entitlement_module.dart';
import '../../domain/entitlement_scope_type.dart';
import '../../domain/entitlement_status.dart';
import '../identity/entitlement_grant_id_generator.dart';

/// Grants (or replaces the existing grant for) an [EntitlementModule] at
/// one scope — admin-only (`PosAuthorizedAction.manageEntitlements`).
/// "No payment/subscription billing in this phase" — this records the
/// *result* of a subscription decision made elsewhere (today, entirely
/// out of band/manual), never processes a payment itself.
class GrantModuleEntitlement {
  const GrantModuleEntitlement({
    required PosAuthorizationPolicy authorizationPolicy,
    required EntitlementGrantIdGenerator idGenerator,
    required EntitlementGrantRepository repository,
    required EntitlementAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final EntitlementGrantIdGenerator _idGenerator;
  final EntitlementGrantRepository _repository;
  final EntitlementAuditEntryRepository _auditRepository;

  Future<EntitlementGrant> call({
    required EntitlementModule module,
    required EntitlementScopeType scopeType,
    required String scopeId,
    EntitlementStatus status = EntitlementStatus.trial,
    DateTime? startsAt,
    DateTime? expiresAt,
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

    final existing =
        await _repository.findByModuleAndScope(module, scopeType, scopeId);
    final grant = EntitlementGrant(
      id: existing?.id ?? _idGenerator.nextEntitlementGrantId(),
      module: module,
      scopeType: scopeType,
      scopeId: scopeId,
      status: status,
      startsAt: startsAt,
      expiresAt: expiresAt,
      grantedByStaffId: performedByStaffId,
      grantedAt: performedAt,
      revision: (existing?.revision ?? 0) + 1,
    );
    await _repository.save(grant);

    await _auditRepository.appendEvent(EntitlementAuditEntry(
      id: '${grant.id}-audit-granted-${performedAt.microsecondsSinceEpoch}',
      actorId: performedByStaffId,
      type: EntitlementAuditEventType.entitlementGranted,
      description: 'Entitlement "${module.name}" granted (${status.name}) for '
          '${scopeType.name}:$scopeId',
      targetEntityId: grant.id,
      newStateName: status.name,
      timestamp: performedAt,
    ));

    return grant;
  }
}
