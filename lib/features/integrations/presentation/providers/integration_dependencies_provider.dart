import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../marketplace/presentation/providers/marketplace_dependencies_provider.dart';
import '../../../payment_hub/presentation/providers/payment_hub_dependencies_provider.dart';
import '../../../pos/presentation/providers/actor_session_provider.dart';
import '../../application/identity/integration_credential_ref_id_generator.dart';
import '../../application/identity/tenant_integration_configuration_id_generator.dart';
import '../../application/identity/webhook_delivery_record_id_generator.dart';
import '../../application/use_cases/build_integration_audit_center_projection.dart';
import '../../application/use_cases/build_provider_health_projection.dart';
import '../../data/integration_audit_entry_repository.dart';
import '../../data/integration_credential_ref_repository.dart';
import '../../data/integration_credential_storage.dart';
import '../../data/tenant_integration_configuration_repository.dart';
import '../../data/webhook_delivery_record_repository.dart';
import '../../domain/integration_provider_adapter.dart';
import '../../domain/integration_provider_category.dart';
import '../../domain/integration_provider_registry.dart';
import '../../domain/webhook_signature_verifier.dart';

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

/// Phase 8K — Credential Management. The real, `flutter_secure_storage`-
/// backed implementation; see `IntegrationCredentialStorage`'s own doc
/// comment for why no use case in this codebase ever reads a value back
/// out of this provider.
final integrationCredentialStorageProvider =
    Provider<IntegrationCredentialStorage>((ref) {
  return const SecureIntegrationCredentialStorage();
});

final integrationCredentialRefRepositoryProvider =
    Provider<IntegrationCredentialRefRepository>((ref) {
  return InMemoryIntegrationCredentialRefRepository();
});

final integrationCredentialRefIdGeneratorProvider =
    Provider<IntegrationCredentialRefIdGenerator>((ref) {
  return SequentialIntegrationCredentialRefIdGenerator();
});

/// Phase 8L — Webhook Foundation. `UnverifiedWebhookSignatureVerifier`
/// is the only implementation — see its own doc comment for why (no
/// `crypto` dependency exists yet, and adding one is a new-dependency
/// decision this provider does not make silently).
final webhookSignatureVerifierProvider =
    Provider<WebhookSignatureVerifier>((ref) {
  return const UnverifiedWebhookSignatureVerifier();
});

final webhookDeliveryRecordRepositoryProvider =
    Provider<WebhookDeliveryRecordRepository>((ref) {
  return InMemoryWebhookDeliveryRecordRepository();
});

final webhookDeliveryRecordIdGeneratorProvider =
    Provider<WebhookDeliveryRecordIdGenerator>((ref) {
  return SequentialWebhookDeliveryRecordIdGenerator();
});

/// Phase 8M — Provider Health Monitoring. Phase 8 closure sprint: now
/// independently authorizes itself (`docs/decisions.md` ADR-025),
/// wired with the real `posAuthorizationPolicyProvider` rather than
/// relying on the consuming screen's `RoleGate` alone.
final buildProviderHealthProjectionProvider =
    Provider<BuildProviderHealthProjection>((ref) {
  return BuildProviderHealthProjection(
    authorizationPolicy: ref.watch(posAuthorizationPolicyProvider),
    providerRegistry: ref.watch(integrationProviderRegistryProvider),
    tenantIntegrationRepository:
        ref.watch(tenantIntegrationConfigurationRepositoryProvider),
  );
});

/// Phase 8N — Integration Audit trail. Cross-feature wiring of
/// marketplace/payment-hub audit repositories mirrors
/// `admin_dependencies_provider.dart`'s `buildAuditCenterProjectionProvider`
/// (Phase 6M) precedent for the same "unify several bounded contexts'
/// audit trails" shape. Phase 8 closure sprint: now independently
/// authorizes itself, same reasoning as
/// `buildProviderHealthProjectionProvider` above.
final buildIntegrationAuditCenterProjectionProvider =
    Provider<BuildIntegrationAuditCenterProjection>((ref) {
  return BuildIntegrationAuditCenterProjection(
    authorizationPolicy: ref.watch(posAuthorizationPolicyProvider),
    integrationAuditRepository:
        ref.watch(integrationAuditEntryRepositoryProvider),
    marketplaceAuditRepository:
        ref.watch(marketplaceAuditEntryRepositoryProvider),
    paymentHubAuditRepository:
        ref.watch(paymentHubAuditEntryRepositoryProvider),
  );
});
