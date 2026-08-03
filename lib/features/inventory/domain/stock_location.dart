/// A physical storage area inside one branch (a walk-in cooler, dry
/// storage, the bar) — Phase 7 (`docs/decisions.md` ADR-024). Always
/// [branchId]-scoped — "physical stock must be branch/location scoped."
/// Distinct from [Warehouse], which serves an organization/restaurant
/// across branches, not one branch's own storage.
class StockLocation {
  const StockLocation({
    required this.id,
    required this.branchId,
    required this.name,
    this.isActive = true,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String branchId;
  final String name;
  final bool isActive;
  final DateTime createdAt;
  final int revision;

  StockLocation copyWith({
    String? name,
    bool? isActive,
    required int revision,
  }) {
    return StockLocation(
      id: id,
      branchId: branchId,
      name: name ?? this.name,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
