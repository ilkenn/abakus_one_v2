import '../../../../core/errors/business_rule_violation.dart';
import '../../../integrations/domain/integration_provider_category.dart';
import '../../../integrations/domain/integration_provider_registry.dart';
import '../../../integrations/data/tenant_integration_configuration_repository.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/marketplace_account_repository.dart';
import '../../data/marketplace_audit_entry_repository.dart';
import '../../domain/audit/marketplace_audit_entry.dart';
import '../../domain/audit/marketplace_audit_event_type.dart';
import '../../domain/marketplace_account.dart';
import '../identity/marketplace_account_id_generator.dart';

/// Creates a [MarketplaceAccount] — Phase 8 (`docs/decisions.md`
/// ADR-025), the "Provider → Marketplace Account" step, tenantOwner-
/// only (`PosAuthorizedAction.manageTenantIntegrations`, Phase 8B),
/// organization-scoped. Requires the tenant to have already **enabled**
/// [providerId] via `SetTenantIntegrationEnabled` (Phase 8H) — an
/// account cannot be created for a provider the tenant hasn't turned on
/// — and requires [providerId] to actually be a
/// [IntegrationProviderCategory.marketplace]-category entry in the
/// platform registry (Phase 8G), not e.g. a payment provider id.
class CreateMarketplaceAccount {
  const CreateMarketplaceAccount({
    required PosAuthorizationPolicy authorizationPolicy,
    required IntegrationProviderRegistry providerRegistry,
    required TenantIntegrationConfigurationRepository
        tenantIntegrationRepository,
    required MarketplaceAccountIdGenerator idGenerator,
    required MarketplaceAccountRepository repository,
    required MarketplaceAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _providerRegistry = providerRegistry,
        _tenantIntegrationRepository = tenantIntegrationRepository,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final IntegrationProviderRegistry _providerRegistry;
  final TenantIntegrationConfigurationRepository _tenantIntegrationRepository;
  final MarketplaceAccountIdGenerator _idGenerator;
  final MarketplaceAccountRepository _repository;
  final MarketplaceAuditEntryRepository _auditRepository;

  Future<MarketplaceAccount> call({
    required String organizationId,
    required String providerId,
    required String accountLabel,
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
    if (provider == null ||
        provider.category != IntegrationProviderCategory.marketplace) {
      throw UnknownIntegrationProviderViolation(providerId: providerId);
    }

    final tenantConfig =
        await _tenantIntegrationRepository.findByOrganizationAndProvider(
      organizationId,
      providerId,
    );
    if (tenantConfig == null || !tenantConfig.enabled) {
      throw IntegrationProviderNotEnabledViolation(providerId: providerId);
    }

    final account = MarketplaceAccount(
      id: _idGenerator.nextMarketplaceAccountId(),
      organizationId: organizationId,
      providerId: providerId,
      accountLabel: accountLabel,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(account);

    await _auditRepository.appendEvent(MarketplaceAuditEntry(
      id: '${account.id}-audit-created',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: MarketplaceAuditEventType.accountCreated,
      description: 'Marketplace account "$accountLabel" created for provider '
          '"$providerId"',
      targetEntityId: account.id,
      timestamp: performedAt,
    ));

    return account;
  }
}
