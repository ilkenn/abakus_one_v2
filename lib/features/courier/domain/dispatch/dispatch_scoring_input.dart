/// One courier candidate's scoring inputs for one delivery — the raw
/// factors `DispatchScorer` weighs. Distance is a straight-line estimate
/// (never a real routing distance — no mapping provider exists).
class DispatchScoringInput {
  const DispatchScoringInput({
    required this.courierId,
    required this.isAvailable,
    required this.isEligibleForBranch,
    required this.activeDeliveryCount,
    required this.capacity,
    this.distanceEstimateMeters,
    required this.packageWaitSeconds,
    required this.recentRejectionCount,
    this.isVehicleSuitable = true,
  });

  final String courierId;
  final bool isAvailable;
  final bool isEligibleForBranch;
  final int activeDeliveryCount;
  final int capacity;
  final double? distanceEstimateMeters;
  final int packageWaitSeconds;
  final int recentRejectionCount;
  final bool isVehicleSuitable;

  bool get hasCapacity => activeDeliveryCount < capacity;
}
