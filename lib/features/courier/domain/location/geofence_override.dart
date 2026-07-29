import 'geofence_zone_type.dart';

/// An immutable, manager-authorized override of a failed/insufficient
/// geofence evaluation — "manual manager override with immutable reason."
/// Never editable or deletable once recorded.
class GeofenceOverride {
  const GeofenceOverride({
    required this.id,
    required this.deliveryId,
    required this.zoneType,
    required this.reason,
    required this.approvedByStaffId,
    required this.approvedAt,
  });

  final String id;
  final String deliveryId;
  final GeofenceZoneType zoneType;
  final String reason;
  final String approvedByStaffId;
  final DateTime approvedAt;
}
