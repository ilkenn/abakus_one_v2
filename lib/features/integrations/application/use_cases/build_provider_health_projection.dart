import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/tenant_integration_configuration_repository.dart';
import '../../domain/integration_provider_registry.dart';
import '../../domain/provider_health_entry.dart';

/// Builds the Provider Health read-model for one tenant — Phase 8
/// (`docs/decisions.md` ADR-025), "Provider Health Monitoring." A
/// **projection**, not a merged write-side store, mirroring
/// `BuildDeviceRegistryProjection`'s (Phase 6L) exact reasoning: neither
/// `IntegrationProviderRegistry` nor `TenantIntegrationConfigurationRepository`
/// is touched or rewritten here, only read and normalized into one
/// consistent row shape per provider.
///
/// **Phase 8 closure sprint (`docs/decisions.md` ADR-025)**: independently
/// authorizes itself before touching any repository — never trusts the
/// caller's UI/route/deep-link to have already gated access.
/// `PosAuthorizedAction.manageTenantIntegrations` (the same action
/// `SetTenantIntegrationEnabled`/`TenantIntegrationHubScreen`'s `RoleGate`
/// already use) is checked with the requested `organizationId` in the
/// authorization context, so a caller-supplied organization id can never
/// bypass the organization-scoping rule.
class BuildProviderHealthProjection {
  const BuildProviderHealthProjection({
    required PosAuthorizationPolicy authorizationPolicy,
    required IntegrationProviderRegistry providerRegistry,
    required TenantIntegrationConfigurationRepository
        tenantIntegrationRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _providerRegistry = providerRegistry,
        _tenantIntegrationRepository = tenantIntegrationRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final IntegrationProviderRegistry _providerRegistry;
  final TenantIntegrationConfigurationRepository _tenantIntegrationRepository;

  Future<List<ProviderHealthEntry>> call({
    required String organizationId,
    required String actorStaffId,
  }) async {
    const action = PosAuthorizedAction.manageTenantIntegrations;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: actorStaffId,
      context: {kOrganizationIdAuthorizationContextKey: organizationId},
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final entries = <ProviderHealthEntry>[];

    for (final adapter in _providerRegistry.all) {
      final tenantConfig =
          await _tenantIntegrationRepository.findByOrganizationAndProvider(
        organizationId,
        adapter.providerId,
      );
      final connectionStatus = await adapter.checkConnection();

      entries.add(ProviderHealthEntry(
        providerId: adapter.providerId,
        category: adapter.category,
        displayName: adapter.displayName,
        tenantEnabled: tenantConfig?.enabled ?? false,
        connectionStatus: connectionStatus,
      ));
    }

    return List.unmodifiable(entries);
  }
}
