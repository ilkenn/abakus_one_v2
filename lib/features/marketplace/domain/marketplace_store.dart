import 'marketplace_account_status.dart';

/// One store listed under a [MarketplaceAccount] — Phase 8
/// (`docs/decisions.md` ADR-025), "Marketplace Account → Marketplace
/// Store." **One account may own multiple stores** (e.g. one
/// Yemeksepeti seller account listing several physical storefronts).
/// Reuses [MarketplaceAccountStatus] rather than a near-identical
/// duplicate enum — both are the same active/suspended/archived
/// lifecycle shape.
class MarketplaceStore {
  const MarketplaceStore({
    required this.id,
    required this.marketplaceAccountId,
    required this.externalStoreId,
    required this.storeName,
    this.status = MarketplaceAccountStatus.active,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String marketplaceAccountId;

  /// The marketplace's own store identifier — a fully opaque string,
  /// never assumed to follow any particular provider's format (each
  /// provider issues its own).
  final String externalStoreId;

  final String storeName;
  final MarketplaceAccountStatus status;
  final DateTime createdAt;
  final int revision;

  MarketplaceStore copyWith({
    String? storeName,
    MarketplaceAccountStatus? status,
    required int revision,
  }) {
    return MarketplaceStore(
      id: id,
      marketplaceAccountId: marketplaceAccountId,
      externalStoreId: externalStoreId,
      storeName: storeName ?? this.storeName,
      status: status ?? this.status,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
