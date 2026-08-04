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
import '../identity/integration_credential_ref_id_generator.dart';

/// Stores a tenant's secret for a provider — Phase 8
/// (`docs/decisions.md` ADR-025), Credential Management (8K).
/// tenantOwner-only (`PosAuthorizedAction.manageTenantIntegrations`),
/// organization-scoped.
///
/// **[value] is written only to `IntegrationCredentialStorage`
/// (`flutter_secure_storage`-backed) — never to the returned
/// [IntegrationCredentialRef], never to the audit entry's
/// [IntegrationAuditEntry.description], never logged.** This is a
/// structural guarantee, not caller discipline: the domain type this
/// use case returns has no field capable of holding it.
///
/// Re-calling for the same `(organizationId, providerId, kind)`
/// overwrites the stored value at the same `storageKey` and bumps the
/// ref's revision, rather than creating a second, stale credential.
class StoreIntegrationCredential {
  const StoreIntegrationCredential({
    required PosAuthorizationPolicy authorizationPolicy,
    required IntegrationCredentialStorage storage,
    required IntegrationCredentialRefIdGenerator idGenerator,
    required IntegrationCredentialRefRepository repository,
    required IntegrationAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _storage = storage,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final IntegrationCredentialStorage _storage;
  final IntegrationCredentialRefIdGenerator _idGenerator;
  final IntegrationCredentialRefRepository _repository;
  final IntegrationAuditEntryRepository _auditRepository;

  Future<IntegrationCredentialRef> call({
    required String organizationId,
    required String providerId,
    required IntegrationCredentialKind kind,
    required String value,
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
    final storageKey =
        existing?.storageKey ?? '$organizationId-$providerId-${kind.name}';
    await _storage.writeValue(storageKey, value);

    final ref = existing?.copyWith(
          revoked: false,
          revision: existing.revision + 1,
        ) ??
        IntegrationCredentialRef(
          id: _idGenerator.nextIntegrationCredentialRefId(),
          organizationId: organizationId,
          providerId: providerId,
          kind: kind,
          storageKey: storageKey,
          createdAt: performedAt,
          revision: 1,
        );
    await _repository.save(ref);

    await _auditRepository.appendEvent(IntegrationAuditEntry(
      id: '${ref.id}-audit-stored-${performedAt.microsecondsSinceEpoch}',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: IntegrationAuditEventType.credentialStored,
      description: 'Credential of kind "${kind.name}" stored for provider '
          '"$providerId"',
      targetEntityId: ref.id,
      timestamp: performedAt,
    ));

    return ref;
  }
}
