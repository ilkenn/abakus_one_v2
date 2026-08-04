import 'integration_connection_status.dart';
import 'integration_provider_category.dart';

/// One row of the Provider Health read-model — Phase 8
/// (`docs/decisions.md` ADR-025), "Provider Health Monitoring."
/// A normalized projection combining the platform's
/// `IntegrationProviderRegistry` catalog (8G) with one tenant's own
/// `TenantIntegrationConfiguration` (8H) — mirrors
/// `DeviceRegistryEntry`'s (Phase 6L) established projection shape.
///
/// [lastCheckedAt] is honestly `null` today — no adapter in this
/// codebase has ever performed a real connection check
/// (`UnconfiguredIntegrationProviderAdapter.checkConnection` always
/// resolves synchronously to [IntegrationConnectionStatus.notConfigured]
/// without contacting anything) — the same "honest absence, not a
/// fabricated value" rule `DeviceRegistryEntry.lastConnectionAt`
/// already established.
class ProviderHealthEntry {
  const ProviderHealthEntry({
    required this.providerId,
    required this.category,
    required this.displayName,
    required this.tenantEnabled,
    required this.connectionStatus,
    this.lastCheckedAt,
  });

  final String providerId;
  final IntegrationProviderCategory category;
  final String displayName;

  /// Whether the current tenant has enabled this provider via
  /// `SetTenantIntegrationEnabled` (8H) — `false` for a provider the
  /// platform catalogs but this tenant has never configured at all.
  final bool tenantEnabled;

  final IntegrationConnectionStatus connectionStatus;
  final DateTime? lastCheckedAt;
}
