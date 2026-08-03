import 'inventory_unit.dart';

/// One food ingredient's master data — Phase 7 (`docs/decisions.md`
/// ADR-024). Organization-scoped ("no global mutable ingredient shared
/// across unrelated tenants") — every `Ingredient` belongs to exactly
/// one [organizationId], never shared or edited across tenants. A
/// future platform reference catalog (explicitly optional per the
/// brief — "a platform reference catalog **may** exist") is not built
/// this phase; every `Ingredient` today is directly tenant-authored,
/// which trivially satisfies "tenant inventory records must be
/// independent snapshots" since there is nothing mutable upstream to
/// snapshot from yet.
class Ingredient {
  const Ingredient({
    required this.id,
    required this.organizationId,
    required this.name,
    this.category,
    required this.baseUnit,
    this.isActive = true,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String name;

  /// Free-text category (e.g. "Protein", "Sebze", "Sos") — a fixed enum
  /// would need to anticipate every tenant's own taxonomy; kept as text
  /// like `MenuCategory.name` already is elsewhere in this codebase.
  final String? category;

  /// The unit this ingredient's quantities are normally expressed and
  /// costed in (e.g. `InventoryUnit.gram` for chicken breast,
  /// `InventoryUnit.piece` for a bun).
  final InventoryUnit baseUnit;

  final bool isActive;
  final DateTime createdAt;
  final int revision;

  Ingredient copyWith({
    String? name,
    String? category,
    bool clearCategory = false,
    InventoryUnit? baseUnit,
    bool? isActive,
    required int revision,
  }) {
    return Ingredient(
      id: id,
      organizationId: organizationId,
      name: name ?? this.name,
      category: clearCategory ? null : (category ?? this.category),
      baseUnit: baseUnit ?? this.baseUnit,
      isActive: isActive ?? this.isActive,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
