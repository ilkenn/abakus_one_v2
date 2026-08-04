import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/tenant_integration_configuration_id_generator.dart';
import '../../data/integration_audit_entry_repository.dart';
import '../../data/tenant_integration_configuration_repository.dart';
import '../../domain/integration_provider_adapter.dart';
import '../../domain/integration_provider_category.dart';
import '../../domain/integration_provider_registry.dart';

/// Central Riverpod wiring for `features/integrations` — Phase 8
/// (`docs/decisions.md` ADR-025).
///
/// [integrationProviderRegistryProvider] is seeded with every candidate
/// provider named anywhere in this codebase's own documentation —
/// marketplace names from `docs/business_rules.md` BR-MKT-002
/// (Yemeksepeti, Getir Yemek, Trendyol Yemek, Migros Yemek, TruYemek)
/// and payment names from the pre-existing `PaymentProviderId` enum
/// (Sprint 3C) — every one an [UnconfiguredIntegrationProviderAdapter],
/// since "do NOT integrate providers yet, only create provider-neutral
/// architecture" applies identically here. Marketplace Hub (8I)/Payment
/// Hub (8J) read from this same registry rather than each maintaining
/// a separate provider list.
final integrationProviderRegistryProvider =
    Provider<IntegrationProviderRegistry>((ref) {
  return IntegrationProviderRegistry(const [
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.marketplace,
      providerId: 'yemeksepeti',
      displayName: 'Yemeksepeti',
    ),
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.marketplace,
      providerId: 'getirYemek',
      displayName: 'Getir Yemek',
    ),
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.marketplace,
      providerId: 'trendyolYemek',
      displayName: 'Trendyol Yemek',
    ),
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.marketplace,
      providerId: 'migrosYemek',
      displayName: 'Migros Yemek',
    ),
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.marketplace,
      providerId: 'truYemek',
      displayName: 'TruYemek',
    ),
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.payment,
      providerId: 'iyzico',
      displayName: 'iyzico',
    ),
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.payment,
      providerId: 'stripe',
      displayName: 'Stripe',
    ),
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.payment,
      providerId: 'adyen',
      displayName: 'Adyen',
    ),
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.payment,
      providerId: 'odeal',
      displayName: 'ÖDeal',
    ),
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.payment,
      providerId: 'pluxee',
      displayName: 'Pluxee',
    ),
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.payment,
      providerId: 'multinet',
      displayName: 'Multinet',
    ),
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.payment,
      providerId: 'setcard',
      displayName: 'Setcard',
    ),
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.payment,
      providerId: 'edenred',
      displayName: 'Edenred',
    ),
    UnconfiguredIntegrationProviderAdapter(
      category: IntegrationProviderCategory.payment,
      providerId: 'metropolCard',
      displayName: 'MetropolCard',
    ),
  ]);
});

final tenantIntegrationConfigurationRepositoryProvider =
    Provider<TenantIntegrationConfigurationRepository>((ref) {
  return InMemoryTenantIntegrationConfigurationRepository();
});

final tenantIntegrationConfigurationIdGeneratorProvider =
    Provider<TenantIntegrationConfigurationIdGenerator>((ref) {
  return SequentialTenantIntegrationConfigurationIdGenerator();
});

final integrationAuditEntryRepositoryProvider =
    Provider<IntegrationAuditEntryRepository>((ref) {
  return InMemoryIntegrationAuditEntryRepository();
});
