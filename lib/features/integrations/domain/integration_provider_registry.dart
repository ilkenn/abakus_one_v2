import 'integration_provider_adapter.dart';
import 'integration_provider_category.dart';

/// A read-only lookup over every [IntegrationProviderAdapter] this
/// build knows about — Phase 8 (`docs/decisions.md` ADR-025). Mirrors
/// `PaymentService`'s existing `Map<PaymentProviderId,
/// PaymentProviderAdapter>` shape (Sprint 3C), generalized across every
/// [IntegrationProviderCategory] rather than payments only. This is the
/// **platform-level catalog of which providers exist at all** (the
/// kickoff's own `managePlatformIntegrationCatalog`, Phase 8A) — a
/// tenant's own selection of which of these it has actually configured
/// is a separate, per-tenant concern the Integration Hub (8H) and
/// Credential Management (8K) own, not this registry.
class IntegrationProviderRegistry {
  IntegrationProviderRegistry(List<IntegrationProviderAdapter> adapters)
      : _byId = {for (final a in adapters) a.providerId: a};

  final Map<String, IntegrationProviderAdapter> _byId;

  IntegrationProviderAdapter? findByProviderId(String providerId) =>
      _byId[providerId];

  List<IntegrationProviderAdapter> findByCategory(
    IntegrationProviderCategory category,
  ) {
    return List.unmodifiable(
      _byId.values.where((a) => a.category == category),
    );
  }

  List<IntegrationProviderAdapter> get all => List.unmodifiable(_byId.values);
}
