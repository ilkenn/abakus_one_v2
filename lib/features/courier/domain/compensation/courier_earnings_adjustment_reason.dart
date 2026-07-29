/// A predefined reason for a manager-created [CourierEarningsAdjustment] —
/// **the only reasons an adjustment may ever be recorded under**, mirroring
/// `DeliveryFailureReason`'s own "no unrestricted free-text reason field"
/// discipline.
enum CourierEarningsAdjustmentReason {
  gpsProblem,
  customerComplaint,
  restaurantDelay,
  systemFailure,
  manualCorrection,
}
