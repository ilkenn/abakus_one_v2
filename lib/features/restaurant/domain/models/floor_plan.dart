/// One named floor/area layout at a [Branch] — e.g. "Zemin Kat", "Teras",
/// "Kış Bahçesi". A branch may have multiple [FloorPlan]s; each
/// [RestaurantTable] belongs to exactly one.
///
/// Deliberately does not model zones/sections as a separate entity —
/// `RestaurantTable.areaName` (free text, added in the table-QR phase) is
/// already the venue-defined sub-section concept; a second [FloorPlan] is
/// the right model for a genuinely distinct physical layout (a different
/// floor, an outdoor terrace with its own map), not for a sub-area within
/// one layout.
class FloorPlan {
  final String id;
  final String branchId;
  final String name;
  final int sortOrder;
  final bool isActive;

  const FloorPlan({
    required this.id,
    required this.branchId,
    required this.name,
    required this.sortOrder,
    required this.isActive,
  });

  FloorPlan copyWith({
    String? id,
    String? branchId,
    String? name,
    int? sortOrder,
    bool? isActive,
  }) {
    return FloorPlan(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      name: name ?? this.name,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
    );
  }
}
