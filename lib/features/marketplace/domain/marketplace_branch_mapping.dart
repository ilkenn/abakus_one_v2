/// Links a [VirtualRestaurant] to the real `Branch` (`features/admin`)
/// that actually fulfills its orders — Phase 8 (`docs/decisions.md`
/// ADR-025), "Virtual Restaurant → Branch Mapping." Each virtual
/// restaurant maps to exactly one fulfilling branch; a single branch
/// may fulfill several virtual restaurants (the many-virtual-
/// restaurants-one-kitchen scenario `VirtualRestaurant`'s own doc
/// comment names).
class MarketplaceBranchMapping {
  const MarketplaceBranchMapping({
    required this.id,
    required this.virtualRestaurantId,
    required this.branchId,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String virtualRestaurantId;
  final String branchId;
  final DateTime createdAt;
  final int revision;
}
