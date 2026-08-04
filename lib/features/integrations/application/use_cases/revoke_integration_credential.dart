import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/integration_audit_entry_repository.dart';
import '../../data/integration_credential_ref_repository.dart';
import '../../data/integration_credential_storage.dart';
import '../../domain/audit/integration_audit_entry.dart';
import '../../domain/audit/integration_audit_event_type.dart';
import '../../domain/integration_credential_kind.dart';
import '../../domain/integration_credential_ref.dart';

/// Revokes a stored credential — Phase 8 (`docs/decisions.md`
/// ADR-025), Credential Management (8K). Deletes the actual secret
/// value from `IntegrationCredentialStorage` and marks the
/// [IntegrationCredentialRef] as revoked (kept, not deleted, so "this
/// tenant once had a credential of this kind" remains auditable —
/// mirrors this codebase's "a status change, not a deletion" pattern
/// already established for `CustomerPhoto`/`StaffMember`).
/// tenantOwner-only, organization-scoped.
class RevokeIntegrationCredential {
  const RevokeIntegrationCredential({
    required PosAuthorizationPolicy authorizationPolicy,
    required IntegrationCredentialStorage storage,
    required IntegrationCredentialRefRepository repository,
    required IntegrationAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _storage = storage,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final IntegrationCredentialStorage _storage;
  final IntegrationCredentialRefRepository _repository;
  final IntegrationAuditEntryRepository _auditRepository;

  Future<IntegrationCredentialRef> call({
    required String organizationId,
    required String providerId,
    required IntegrationCredentialKind kind,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageTenantIntegrations;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
      context: {kOrganizationIdAuthorizationContextKey: organizationId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final existing = await _repository.findByOrganizationProviderAndKind(
      organizationId,
      providerId,
      kind,
    );
    if (existing == null) {
      throw UnknownIntegrationCredentialViolation(
        organizationId: organizationId,
        providerId: providerId,
        kind: kind.name,
      );
    }

    await _storage.deleteValue(existing.storageKey);

    final revoked = existing.copyWith(
      revoked: true,
      revision: existing.revision + 1,
    );
    await _repository.save(revoked);

    await _auditRepository.appendEvent(IntegrationAuditEntry(
      id: '${revoked.id}-audit-revoked-${performedAt.microsecondsSinceEpoch}',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: IntegrationAuditEventType.credentialRevoked,
      description: 'Credential of kind "${kind.name}" revoked for provider '
          '"$providerId"',
      targetEntityId: revoked.id,
      timestamp: performedAt,
    ));

    return revoked;
  }
}
