/// A central storage facility serving an organization/restaurant across
/// multiple branches — Phase 7 (`docs/decisions.md` ADR-024). Unlike
/// [StockLocation] (always one branch's own storage), a [Warehouse] is
/// [restaurantId]-scoped, not branch-scoped — stock physically held
/// here is not yet any one branch's `BranchStock` until transferred
/// (a transfer is just another `StockMovement`, from the warehouse's
/// own location record to a branch `StockLocation`).
class Warehouse {
  const Warehouse({
    required this.id,
    required this.restaurantId,
    required this.name,
    this.isActive = true,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String restaurantId;
  final String name;
  final bool isActive;
  final DateTime createdAt;
  final int revision;

  Warehouse copyWith({
    String? name,
    bool? isActive,
    required int revision,
  }) {
    return Warehouse(
      id: id,
      restaurantId: restaurantId,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
