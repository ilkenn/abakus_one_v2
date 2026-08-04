import 'integration_provider_category.dart';

/// One tenant's decision to enable (or disable) a specific provider
/// from the platform's `IntegrationProviderRegistry` catalog — Phase 8
/// (`docs/decisions.md` ADR-025), the Integration Hub's own tenant-
/// facing record. Distinct from the registry itself (8G, platform-
/// wide, "which providers exist at all") — this is "has *this* tenant
/// turned *this* provider on," mirroring the same
/// platform-catalog-vs-tenant-selection split `EntitlementModule`
/// (platform-defined) vs. `EntitlementGrant` (tenant-purchased,
/// Phase 7A) already established.
class TenantIntegrationConfiguration {
  const TenantIntegrationConfiguration({
    required this.id,
    required this.organizationId,
    required this.category,
    required this.providerId,
    required this.enabled,
    required this.configuredByStaffId,
    required this.configuredAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final IntegrationProviderCategory category;
  final String providerId;
  final bool enabled;
  final String configuredByStaffId;
  final DateTime configuredAt;
  final int revision;

  TenantIntegrationConfiguration copyWith({
    bool? enabled,
    required String configuredByStaffId,
    required DateTime configuredAt,
    required int revision,
  }) {
    return TenantIntegrationConfiguration(
      id: id,
      organizationId: organizationId,
      category: category,
      providerId: providerId,
      enabled: enabled ?? this.enabled,
      configuredByStaffId: configuredByStaffId,
      configuredAt: configuredAt,
      revision: revision,
    );
  }
}
