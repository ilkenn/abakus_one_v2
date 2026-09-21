import '../../../pos/domain/kds/kitchen_station.dart';

/// A top-level grouping of products on the menu (e.g. "Bowl", "Salata").
class MenuCategory {
  final String id;
  final String name;
  final int sortOrder;
  final bool isActive;

  /// The [KitchenStation] a product in this category routes to when
  /// accepted, absent a more specific rule — `null` falls back to
  /// [KitchenStation.shared], matching every other fail-safe default in
  /// this codebase. Read server-side by `acceptOrderLine.ts`'s
  /// `stationForLine()` (KDS station-based routing, 2026-09-21) via the
  /// category document `catalogMigration.ts` migrates into Firestore.
  final KitchenStation? defaultStation;

  const MenuCategory({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.isActive,
    this.defaultStation,
  });

  MenuCategory copyWith({
    String? id,
    String? name,
    int? sortOrder,
    bool? isActive,
    KitchenStation? defaultStation,
  }) {
    return MenuCategory(
      id: id ?? this.id,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      defaultStation: defaultStation ?? this.defaultStation,
    );
  }
}
