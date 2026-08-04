import 'package:abakus_one_v2/features/integrations/data/tenant_integration_configuration_repository.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_adapter.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_category.dart';
import 'package:abakus_one_v2/features/integrations/domain/integration_provider_registry.dart';
import 'package:abakus_one_v2/features/integrations/domain/tenant_integration_configuration.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorization_policy.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/pos_authorized_action.dart';

class AllowAllMarketplacePolicy implements PosAuthorizationPolicy {
  const AllowAllMarketplacePolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async {
    return const AuthorizationResult(granted: true);
  }
}

class DenyAllMarketplacePolicy implements PosAuthorizationPolicy {
  const DenyAllMarketplacePolicy();

  @override
  Future<AuthorizationResult> authorize({
    required PosAuthorizedAction action,
    required String actorStaffId,
    Map<String, String> context = const {},
  }) async {
    return const AuthorizationResult(granted: false, reason: 'denied');
  }
}

IntegrationProviderRegistry buildTestProviderRegistry() {
  return IntegrationProviderRegistry(const [
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.marketplace,
      providerId: 'yemeksepeti',
      displayName: 'Yemeksepeti',
    ),
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.payment,
      providerId: 'iyzico',
      displayName: 'iyzico',
    ),
  ]);
}

/// Seeds [repository] with an enabled `yemeksepeti` configuration for
/// `org-1` — the precondition `CreateMarketplaceAccount` requires.
Future<TenantIntegrationConfigurationRepository>
    seedEnabledYemeksepetiConfig() async {
  final repository = InMemoryTenantIntegrationConfigurationRepository();
  await repository.save(TenantIntegrationConfiguration(
    id: 'config-1',
    organizationId: 'org-1',
    category: IntegrationProviderCategory.marketplace,
    providerId: 'yemeksepeti',
    enabled: true,
    configuredByStaffId: 'owner-1',
    configuredAt: DateTime(2026, 1, 1),
    revision: 1,
  ));
  return repository;
}
