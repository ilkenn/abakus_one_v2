import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_failure.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_failure_reason.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_failure_responsibility.dart';
import 'package:flutter_test/flutter_test.dart';

DeliveryFailure _failure(DeliveryFailureReason reason) {
  return DeliveryFailure(
    id: 'failure-1',
    deliveryId: 'delivery-1',
    reasonCode: reason,
    courierNote: '',
    recordedByStaffId: 'staff-1',
    recordedAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('DeliveryFailureResponsibilityMapper', () {
    test('customer-caused reasons map to customer responsibility', () {
      for (final reason in [
        DeliveryFailureReason.customerUnavailable,
        DeliveryFailureReason.customerRefused,
        DeliveryFailureReason.incorrectAddress,
        DeliveryFailureReason.unreachableCustomer,
        DeliveryFailureReason.accessDenied,
        DeliveryFailureReason.paymentNotCollected,
      ]) {
        expect(DeliveryFailureResponsibilityMapper.forReason(reason),
            DeliveryFailureResponsibility.customer);
      }
    });

    test('restaurant-caused reasons never map to customer responsibility', () {
      expect(
        DeliveryFailureResponsibilityMapper.forReason(
            DeliveryFailureReason.restaurantPreparationProblem),
        DeliveryFailureResponsibility.restaurant,
      );
      expect(
        DeliveryFailureResponsibilityMapper.forReason(
            DeliveryFailureReason.packageProblem),
        DeliveryFailureResponsibility.restaurant,
      );
    });

    test('courier-caused reasons map to courier responsibility', () {
      expect(
        DeliveryFailureResponsibilityMapper.forReason(
            DeliveryFailureReason.courierVehicleProblem),
        DeliveryFailureResponsibility.courier,
      );
      expect(
        DeliveryFailureResponsibilityMapper.forReason(
            DeliveryFailureReason.courierOperationalProblem),
        DeliveryFailureResponsibility.courier,
      );
    });

    test('force majeure and system/manager reasons map correctly', () {
      expect(
        DeliveryFailureResponsibilityMapper.forReason(
            DeliveryFailureReason.weatherOrForceMajeure),
        DeliveryFailureResponsibility.forceMajeure,
      );
      expect(
        DeliveryFailureResponsibilityMapper.forReason(
            DeliveryFailureReason.systemOrNavigationProblem),
        DeliveryFailureResponsibility.system,
      );
      expect(
        DeliveryFailureResponsibilityMapper.forReason(
            DeliveryFailureReason.managerCancellation),
        DeliveryFailureResponsibility.manager,
      );
    });
  });

  group('DeliveryFailure.mayEmitCustomerRiskSignal', () {
    test('true only for customer-attributable failures', () {
      final customerCaused = _failure(DeliveryFailureReason.customerRefused);
      expect(customerCaused.mayEmitCustomerRiskSignal, isTrue);
    });

    test(
        'false for restaurant/courier/system/force-majeure/manager '
        'failures — these must never increase customer risk', () {
      for (final reason in [
        DeliveryFailureReason.restaurantPreparationProblem,
        DeliveryFailureReason.courierVehicleProblem,
        DeliveryFailureReason.systemOrNavigationProblem,
        DeliveryFailureReason.weatherOrForceMajeure,
        DeliveryFailureReason.managerCancellation,
      ]) {
        expect(_failure(reason).mayEmitCustomerRiskSignal, isFalse,
            reason: 'reason=$reason must not emit a customer-risk signal');
      }
    });

    test('responsibility is frozen at construction and matches reasonCode', () {
      final failure = _failure(DeliveryFailureReason.packageProblem);
      expect(failure.responsibility, DeliveryFailureResponsibility.restaurant);
    });
  });
}
