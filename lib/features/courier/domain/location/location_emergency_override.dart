/// An immutable, manager-authorized escape hatch letting a courier keep
/// progressing a specific delivery (or, when [deliveryId] is `null`,
/// their general operational actions) while location is reported
/// unavailable — "manager override must require authorization, reason,
/// timestamp, and audit evidence." Mirrors `GeofenceOverride`'s exact
/// shape (Phase 5) as a deliberately separate type, one level up: this
/// overrides the *gate itself*, not one geofence check.
class LocationEmergencyOverride {
  const LocationEmergencyOverride({
    required this.id,
    required this.courierId,
    this.deliveryId,
    required this.reason,
    required this.authorizedByStaffId,
    required this.grantedAt,
    this.expiresAt,
  });

  final String id;
  final String courierId;
  final String? deliveryId;
  final String reason;
  final String authorizedByStaffId;
  final DateTime grantedAt;

  /// `null` means open-ended for the remainder of the current shift — a
  /// manager may still grant a bounded window instead.
  final DateTime? expiresAt;

  bool isActiveAt(DateTime at) {
    final expiry = expiresAt;
    return expiry == null || at.isBefore(expiry);
  }
}
