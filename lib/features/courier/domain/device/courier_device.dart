/// A courier's registered mobile device — structurally mirrors
/// `KitchenDisplayDevice` (Phase 4) but is a deliberately separate type,
/// per the explicit instruction not to couple courier domain objects
/// directly to KDS-specific contracts. Mutable registry entity.
class CourierDevice {
  const CourierDevice({
    required this.id,
    required this.courierId,
    this.platformLabel = '',
    this.isActive = true,
    required this.registeredAt,
  });

  final String id;
  final String courierId;

  /// Free-text platform/model label (e.g. `'Android'`, `'iOS'`) — display
  /// only, never used for any authorization/business-rule decision.
  final String platformLabel;

  final bool isActive;
  final DateTime registeredAt;

  CourierDevice copyWith({bool? isActive}) {
    return CourierDevice(
      id: id,
      courierId: courierId,
      platformLabel: platformLabel,
      isActive: isActive ?? this.isActive,
      registeredAt: registeredAt,
    );
  }
}
