/// The manager-controlled order a courier should work through their
/// currently-active deliveries — Sprint 5C Part 5. Append-only via
/// [revision] (mirrors `CourierAvailability`'s shape) — a reorder is
/// always a new revision, never an edit of the previous one.
///
/// **Courier cannot modify this** — no use case in the courier-facing
/// surface writes to `CourierDeliverySequenceRepository`; only
/// `ReorderCourierDeliverySequence` (manager-authorized) does.
class CourierDeliverySequence {
  const CourierDeliverySequence({
    required this.courierId,
    required this.branchId,
    required this.orderedDeliveryIds,
    required this.updatedAt,
    required this.updatedByStaffId,
    required this.revision,
  });

  final String courierId;
  final String branchId;

  /// In manager-set order — first is "do this one next."
  final List<String> orderedDeliveryIds;
  final DateTime updatedAt;
  final String updatedByStaffId;
  final int revision;
}
