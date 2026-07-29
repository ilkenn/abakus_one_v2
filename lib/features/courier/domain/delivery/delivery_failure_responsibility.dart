import 'delivery_failure_reason.dart';

/// Who a [DeliveryFailure] is attributable to — the sole input to whether
/// a customer-risk signal may be emitted (only [customer] may). This is
/// deliberately a closed, small classification, not a free-text field —
/// every [DeliveryFailureReason] maps to exactly one of these, frozen at
/// classification time so a later reason-taxonomy change can never
/// retroactively alter an already-recorded failure's responsibility.
enum DeliveryFailureResponsibility {
  customer,
  restaurant,
  courier,
  system,
  forceMajeure,
  manager,
}

/// The single source of truth for reason → responsibility mapping — pure,
/// deterministic, exhaustive (a compile error if a new
/// [DeliveryFailureReason] value is added without updating this).
abstract final class DeliveryFailureResponsibilityMapper {
  DeliveryFailureResponsibilityMapper._();

  static DeliveryFailureResponsibility forReason(DeliveryFailureReason reason) {
    switch (reason) {
      case DeliveryFailureReason.customerUnavailable:
      case DeliveryFailureReason.customerRefused:
      case DeliveryFailureReason.incorrectAddress:
      case DeliveryFailureReason.unreachableCustomer:
      case DeliveryFailureReason.accessDenied:
      case DeliveryFailureReason.paymentNotCollected:
        return DeliveryFailureResponsibility.customer;
      case DeliveryFailureReason.restaurantPreparationProblem:
      case DeliveryFailureReason.packageProblem:
        return DeliveryFailureResponsibility.restaurant;
      case DeliveryFailureReason.courierVehicleProblem:
      case DeliveryFailureReason.courierOperationalProblem:
        return DeliveryFailureResponsibility.courier;
      case DeliveryFailureReason.systemOrNavigationProblem:
        return DeliveryFailureResponsibility.system;
      case DeliveryFailureReason.weatherOrForceMajeure:
        return DeliveryFailureResponsibility.forceMajeure;
      case DeliveryFailureReason.managerCancellation:
        return DeliveryFailureResponsibility.manager;
    }
  }
}
