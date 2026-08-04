import 'marketplace_account_status.dart';

/// A "virtual brand" listed under a [MarketplaceStore] — Phase 8
/// (`docs/decisions.md` ADR-025), "Marketplace Store → Virtual
/// Restaurant." A common real-world marketplace feature: a single
/// physical kitchen can operate several differently-branded virtual
/// restaurants on the same store (e.g. "Abaküs Bowl" and "Abaküs
/// Vegan," both fulfilled from the same branch) — **one store may own
/// multiple virtual restaurants**.
class VirtualRestaurant {
  const VirtualRestaurant({
    required this.id,
    required this.marketplaceStoreId,
    required this.name,
    this.status = MarketplaceAccountStatus.active,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String marketplaceStoreId;
  final String name;
  final MarketplaceAccountStatus status;
  final DateTime createdAt;
  final int revision;

  VirtualRestaurant copyWith({
    String? name,
    MarketplaceAccountStatus? status,
    required int revision,
  }) {
    return VirtualRestaurant(
      id: id,
      marketplaceStoreId: marketplaceStoreId,
      name: name ?? this.name,
      status: status ?? this.status,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
