/// A manager's decision to assign two or more same-destination deliveries
/// together to one courier — Sprint 5C Part 6. Immutable, append-only —
/// created once by `GroupSameDestinationDeliveries`
/// ("assign together"); choosing "assign separately" instead simply never
/// creates one, and the deliveries proceed exactly as any other unrelated
/// deliveries would (no waived package fee).
class SameDestinationGroup {
  const SameDestinationGroup({
    required this.id,
    required this.branchId,
    required this.courierId,
    required this.deliveryIds,
    required this.groupedByStaffId,
    required this.groupedAt,
  });

  final String id;
  final String branchId;
  final String courierId;

  /// Always 2 or more.
  final List<String> deliveryIds;
  final String groupedByStaffId;
  final DateTime groupedAt;
}
