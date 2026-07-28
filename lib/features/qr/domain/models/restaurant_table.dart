import '../../../restaurant/domain/models/table_shape.dart';

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
///
/// [floorPlanId]/[positionX]/[positionY]/[shape]/[rotationDegrees]/[width]/
/// [height] are Phase 3 Sprint 3D additions for the floor-plan editor and
/// live floor map. Position/shape/size default to a sensible unplaced
/// square so a table can exist (and be assigned to service) before its
/// layout is ever placed on the map — mirrors `TableQrCode`'s own "a table
/// can exist before its QR code is printed" precedent. [floorPlanId] has no
/// default: every table belongs to exactly one floor plan.
class RestaurantTable {
  final String id;
  final String branchId;
  final String floorPlanId;
  final String displayName;

  /// Free-form, venue-defined section/area name (e.g. "Teras", "Salon 2").
  /// Not an enum: restaurants name their own sections, so this is a genuine
  /// open-text field rather than a fixed category.
  final String areaName;

  final int capacity;
  final TableStatus status;
  final int sortOrder;
  final bool isActive;

  /// Top-left position on the floor plan's live map, in the map's own
  /// logical coordinate space (not screen pixels — the rendering layer
  /// scales this to the viewport).
  final double positionX;
  final double positionY;

  final TableShape shape;

  /// Clockwise rotation in degrees, `0` = unrotated.
  final double rotationDegrees;

  final double width;
  final double height;

  const RestaurantTable({
    required this.id,
    required this.branchId,
    required this.floorPlanId,
    required this.displayName,
    required this.areaName,
    required this.capacity,
    required this.status,
    required this.sortOrder,
    required this.isActive,
    this.positionX = 0,
    this.positionY = 0,
    this.shape = TableShape.square,
    this.rotationDegrees = 0,
    this.width = 80,
    this.height = 80,
  });

  /// Whether this table can currently accept a new dine-in QR session.
  bool get isOrderable => isActive && status == TableStatus.available;

  RestaurantTable copyWith({
    String? id,
    String? branchId,
    String? floorPlanId,
    String? displayName,
    String? areaName,
    int? capacity,
    TableStatus? status,
    int? sortOrder,
    bool? isActive,
    double? positionX,
    double? positionY,
    TableShape? shape,
    double? rotationDegrees,
    double? width,
    double? height,
  }) {
    return RestaurantTable(
      id: id ?? this.id,
      branchId: branchId ?? this.branchId,
      floorPlanId: floorPlanId ?? this.floorPlanId,
      displayName: displayName ?? this.displayName,
      areaName: areaName ?? this.areaName,
      capacity: capacity ?? this.capacity,
      status: status ?? this.status,
      sortOrder: sortOrder ?? this.sortOrder,
      isActive: isActive ?? this.isActive,
      positionX: positionX ?? this.positionX,
      positionY: positionY ?? this.positionY,
      shape: shape ?? this.shape,
      rotationDegrees: rotationDegrees ?? this.rotationDegrees,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }
}
