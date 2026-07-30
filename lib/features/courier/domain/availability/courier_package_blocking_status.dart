/// Whether a manager has temporarily blocked a courier from receiving
/// *new* package assignments while they finish their existing ones —
/// Sprint 5C Part 7. Append-only via [revision] (mirrors
/// `CourierAvailability`'s shape) — distinct from
/// `CourierAvailabilityStatus`, which this never mutates: a blocked
/// courier can still be `available`/`busy`, just ineligible for new
/// `DispatchScorer` offers (`DispatchScoringInput
/// .isTemporarilyBlockedFromNewPackages`).
class CourierPackageBlockingStatus {
  const CourierPackageBlockingStatus({
    required this.courierId,
    required this.isBlocked,
    this.reason,
    required this.setByStaffId,
    required this.setAt,
    required this.revision,
  });

  final String courierId;
  final bool isBlocked;
  final String? reason;
  final String setByStaffId;
  final DateTime setAt;
  final int revision;
}
