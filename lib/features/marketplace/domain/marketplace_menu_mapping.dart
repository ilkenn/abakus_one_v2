/// Links one internal `MenuProduct` (`features/menu`) to its listing on
/// a [VirtualRestaurant] — Phase 8 (`docs/decisions.md` ADR-025), the
/// "Marketplace Mapping Engine"'s menu leaf ("Virtual Restaurant → Menu
/// Mapping"). [externalProductId] is the marketplace's own opaque
/// listing identifier — never assumed to match [internalMenuProductId]
/// or follow any particular format.
class MarketplaceMenuMapping {
  const MarketplaceMenuMapping({
    required this.id,
    required this.virtualRestaurantId,
    required this.internalMenuProductId,
    required this.externalProductId,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String virtualRestaurantId;
  final String internalMenuProductId;
  final String externalProductId;
  final DateTime createdAt;
  final int revision;
}
