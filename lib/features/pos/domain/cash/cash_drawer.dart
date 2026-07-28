/// A physical cash drawer at a branch — a registry entity, mutable like
/// `RestaurantTable`/`FloorPlan` (its own current shape is what matters,
/// not a revision history of it; the append-only requirement in this
/// sprint applies to the *financial* records a drawer's sessions produce,
/// not to the drawer registry entry itself).
///
/// A branch may have multiple drawers (`docs/business_rules.md`
/// BR-CASH-001). A drawer's lifecycle across many sessions is tracked by
/// `CashSession`, not duplicated here — `CashDrawer.isActive` only means
/// "still in service," never "currently has an open session" (that's
/// `CashSessionRepository.findActiveByDrawerId`, avoiding two fields that
/// could disagree).
class CashDrawer {
  const CashDrawer({
    required this.id,
    required this.branchId,
    required this.name,
    this.isActive = true,
  });

  final String id;
  final String branchId;
  final String name;
  final bool isActive;

  CashDrawer copyWith({bool? isActive}) {
    return CashDrawer(
      id: id,
      branchId: branchId,
      name: name,
      isActive: isActive ?? this.isActive,
    );
  }
}
