import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/integration_audit_entry_repository.dart';
import '../../data/tenant_integration_configuration_repository.dart';
import '../../domain/audit/integration_audit_entry.dart';
import '../../domain/audit/integration_audit_event_type.dart';
import '../../domain/integration_provider_registry.dart';
import '../../domain/tenant_integration_configuration.dart';
import '../identity/tenant_integration_configuration_id_generator.dart';

/// Enables or disables a platform-registered provider for one tenant —
/// Phase 8 (`docs/decisions.md` ADR-025), tenantOwner-only
/// (`PosAuthorizedAction.manageTenantIntegrations`, Phase 8B),
/// organization-scoped (no role exemption — `ActorSession
/// .organizationAccess`'s own rule). The single write path Marketplace
/// Hub (8I) and Payment Hub (8J) admin surfaces both use to turn a
/// specific provider on/off for their tenant, rather than each
/// inventing their own toggle.
class SetTenantIntegrationEnabled {
  const SetTenantIntegrationEnabled({
    required PosAuthorizationPolicy authorizationPolicy,
    required IntegrationProviderRegistry providerRegistry,
    required TenantIntegrationConfigurationIdGenerator idGenerator,
    required TenantIntegrationConfigurationRepository repository,
    required IntegrationAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _providerRegistry = providerRegistry,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final IntegrationProviderRegistry _providerRegistry;
  final TenantIntegrationConfigurationIdGenerator _idGenerator;
  final TenantIntegrationConfigurationRepository _repository;
  final IntegrationAuditEntryRepository _auditRepository;

  Future<TenantIntegrationConfiguration> call({
    required String organizationId,
    required String providerId,
    required bool enabled,
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

    final provider = _providerRegistry.findByProviderId(providerId);
    if (provider == null) {
      throw UnknownIntegrationProviderViolation(providerId: providerId);
    }

    final existing = await _repository.findByOrganizationAndProvider(
      organizationId,
      providerId,
    );
    final configuration = existing?.copyWith(
          enabled: enabled,
          configuredByStaffId: performedByStaffId,
          configuredAt: performedAt,
          revision: existing.revision + 1,
        ) ??
        TenantIntegrationConfiguration(
          id: _idGenerator.nextTenantIntegrationConfigurationId(),
          organizationId: organizationId,
          category: provider.category,
          providerId: providerId,
          enabled: enabled,
          configuredByStaffId: performedByStaffId,
          configuredAt: performedAt,
          revision: 1,
        );
    await _repository.save(configuration);

    await _auditRepository.appendEvent(IntegrationAuditEntry(
      id: '${configuration.id}-audit-${enabled ? 'enabled' : 'disabled'}-'
          '${performedAt.microsecondsSinceEpoch}',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: enabled
          ? IntegrationAuditEventType.tenantIntegrationEnabled
          : IntegrationAuditEventType.tenantIntegrationDisabled,
      description:
          'Provider "$providerId" ${enabled ? 'enabled' : 'disabled'} for '
          'organization "$organizationId"',
      targetEntityId: configuration.id,
      timestamp: performedAt,
    ));

    return configuration;
  }
}
