import 'integration_connection_status.dart';
import 'integration_provider_category.dart';

/// The shared contract every Integration Hub provider adapter
/// implements — Phase 8 (`docs/decisions.md` ADR-025), the "Provider
/// Adapter architecture" the kickoff names as its own objective,
/// distinct from Marketplace Hub (8I) and Payment Hub (8J), which each
/// implement it for their own concrete providers rather than each
/// inventing a parallel contract.
///
/// Mirrors this codebase's established, repeated provider-adapter
/// template — an abstract interface plus one safe, honest default
/// implementation that never fabricates a connection
/// (`ExchangeRateProvider`/`UnavailableExchangeRateProvider`,
/// `ReceiptPrintProvider`/`NoOpReceiptPrintProvider`,
/// `PaymentProviderAdapter`'s 9 concrete-but-`notConfigured` adapters).
/// "Do NOT integrate providers yet. Only create provider-neutral
/// architecture" (the kickoff's own Payment Hub instruction, applied
/// identically here to every category) — no real vendor SDK call
/// exists behind any adapter this phase builds.
abstract interface class IntegrationProviderAdapter {
  IntegrationProviderCategory get category;

  /// An opaque, category-scoped identifier (e.g. `"iyzico"`,
  /// `"yemeksepeti"`) — kept a plain `String`, not a shared enum, since
  /// each category owns its own closed identifier set
  /// (`PaymentProviderId` already exists for payments; a
  /// `MarketplaceProviderId` is Marketplace Hub's own, Phase 8I).
  String get providerId;

  /// A human-readable name for admin/platform UI — never used for
  /// equality/lookup (that's [providerId]'s job).
  String get displayName;

  /// Never throws — an adapter with no real connection to check
  /// resolves to [IntegrationConnectionStatus.notConfigured] rather
  /// than propagate an exception, the same "an absent seam is safe"
  /// pattern every prior default implementation in this codebase
  /// follows.
  Future<IntegrationConnectionStatus> checkConnection();
}

/// The safe default every category's own "not yet configured" adapter
/// can either use directly or extend — always reports
/// [IntegrationConnectionStatus.notConfigured], never throws, never
/// fabricates a connection.
class UnconfiguredIntegrationProviderAdapter
    implements IntegrationProviderAdapter {
  const UnconfiguredIntegrationProviderAdapter({
    required this.category,
    required this.providerId,
    required this.displayName,
  });

  @override
  final IntegrationProviderCategory category;

  @override
  final String providerId;

  @override
  final String displayName;

  @override
  Future<IntegrationConnectionStatus> checkConnection() async =>
      IntegrationConnectionStatus.notConfigured;
}
