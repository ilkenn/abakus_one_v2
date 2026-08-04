import '../../../../core/errors/business_rule_violation.dart';
import '../../../integrations/data/tenant_integration_configuration_repository.dart';
import '../../../integrations/domain/integration_provider_category.dart';
import '../../../integrations/domain/integration_provider_registry.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../../pos/domain/authorization/real_pos_authorization_policy.dart';
import '../../data/payment_hub_audit_entry_repository.dart';
import '../../data/payment_merchant_account_repository.dart';
import '../../domain/audit/payment_hub_audit_entry.dart';
import '../../domain/audit/payment_hub_audit_event_type.dart';
import '../../domain/payment_merchant_account.dart';
import '../identity/payment_merchant_account_id_generator.dart';

/// Creates a [PaymentMerchantAccount] — Phase 8 (`docs/decisions.md`
/// ADR-025), the "Payment Provider → Merchant Account → Branch" step,
/// tenantOwner-only (`PosAuthorizedAction.manageTenantIntegrations`,
/// Phase 8B), organization-scoped. Mirrors
/// `CreateMarketplaceAccount`'s exact precondition: the tenant must
/// have already **enabled** [providerId] via `SetTenantIntegrationEnabled`
/// (Phase 8H), and [providerId] must be a
/// [IntegrationProviderCategory.payment]-category entry in the platform
/// registry (Phase 8G), not a marketplace provider id.
class CreateMerchantAccount {
  const CreateMerchantAccount({
    required PosAuthorizationPolicy authorizationPolicy,
    required IntegrationProviderRegistry providerRegistry,
    required TenantIntegrationConfigurationRepository
        tenantIntegrationRepository,
    required PaymentMerchantAccountIdGenerator idGenerator,
    required PaymentMerchantAccountRepository repository,
    required PaymentHubAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _providerRegistry = providerRegistry,
        _tenantIntegrationRepository = tenantIntegrationRepository,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final IntegrationProviderRegistry _providerRegistry;
  final TenantIntegrationConfigurationRepository _tenantIntegrationRepository;
  final PaymentMerchantAccountIdGenerator _idGenerator;
  final PaymentMerchantAccountRepository _repository;
  final PaymentHubAuditEntryRepository _auditRepository;

  Future<PaymentMerchantAccount> call({
    required String organizationId,
    required String branchId,
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
        provider.category != IntegrationProviderCategory.payment) {
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

    final account = PaymentMerchantAccount(
      id: _idGenerator.nextPaymentMerchantAccountId(),
      organizationId: organizationId,
      branchId: branchId,
      providerId: providerId,
      accountLabel: accountLabel,
      createdAt: performedAt,
      revision: 1,
    );
    await _repository.save(account);

    await _auditRepository.appendEvent(PaymentHubAuditEntry(
      id: '${account.id}-audit-created',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: PaymentHubAuditEventType.merchantAccountCreated,
      description: 'Payment merchant account "$accountLabel" created for '
          'provider "$providerId" on branch "$branchId"',
      targetEntityId: account.id,
      timestamp: performedAt,
    ));

    return account;
  }
}
