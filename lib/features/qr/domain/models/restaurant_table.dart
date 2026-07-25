/// Operational status of a physical table.
///
/// Deliberately named `TableStatus`, not `Status`, to stay unambiguous once
/// other domains (orders, QR codes, sessions) grow their own status enums.
enum TableStatus { available, occupied, reserved, cleaning, disabled }

/// A physical table at a [Branch].
///
/// Named `RestaurantTable` rather than `Table` to avoid colliding with
/// Flutter's own `Table` widget and general terminology.
///
/// QR identity is intentionally not modeled here — see [TableQrCode]. A
/// table's QR code can be rotated/replaced without ever touching the table
/// record itself.
class RestaurantTable {
  final String id;
  final String branchId;
  final String displayName;

  /// Free-form, venue-defined section/area name (e.g. "Teras", "Salon 2").
  /// Not an enum: restaurants name their own sections, so this is a genuine
  /// open-text field rather than a fixed category.
  final String areaName;

  final int capacity;
  final TableStatus status;
  final int sortOrder;
  final bool isActive;

  const RestaurantTable({
    required this.id,
    required this.branchId,
    required this.displayName,
    required this.areaName,
    required this.capacity,
    required this.status,
    required this.sortOrder,
    required this.isActive,
  });

  /// Whether this table can currently accept a new dine-in QR session.
  bool get isOrderable => isActive && status == TableStatus.available;

  RestaurantTable copyWith({
    String? id,
    String? branchId,
    String? displayName,
    String? areaName,
    int? capacity,
    TableStatus? status,
    int? sortOrder,
    bool? isActive,
  }) {
    return RestaurantTable(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      displayName: displayName ?? this.displayName,
      areaName: areaName ?? this.areaName,
      capacity: capacity ?? this.capacity,
      status: status ?? this.status,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
    );
  }
}
