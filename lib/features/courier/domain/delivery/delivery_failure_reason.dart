/// A predefined failure reason — **the only reasons a failure may ever be
/// recorded under**. No free-text "accusation" field exists anywhere on
/// [DeliveryFailure]; `courierNote` is operational and length-limited,
/// never a substitute for a reason code.
enum DeliveryFailureReason {
  customerUnavailable,
  customerRefused,
  incorrectAddress,
  unreachableCustomer,
  accessDenied,
  paymentNotCollected,
  restaurantPreparationProblem,
  packageProblem,
  courierVehicleProblem,
  courierOperationalProblem,
  systemOrNavigationProblem,
  weatherOrForceMajeure,
  managerCancellation,
}
