import 'package:abakus_one_v2/features/orders/domain/fulfillment/package_preparation_status.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('PackagePreparationTransitions', () {
    test('received moves to pendingAcceptance or cancelled', () {
      expect(
        PackagePreparationTransitions.canTransition(
            PackagePreparationStatus.received,
            PackagePreparationStatus.pendingAcceptance),
        isTrue,
      );
    });

    test(
        'packed can go straight to delivered (no courier leg) or to waitingForCourier',
        () {
      expect(
        PackagePreparationTransitions.canTransition(
            PackagePreparationStatus.packed,
            PackagePreparationStatus.delivered),
        isTrue,
      );
      expect(
        PackagePreparationTransitions.canTransition(
            PackagePreparationStatus.packed,
            PackagePreparationStatus.waitingForCourier),
        isTrue,
      );
    });

    test('exception only returns to preparing or cancelled', () {
      expect(
        PackagePreparationTransitions.canTransition(
            PackagePreparationStatus.exception,
            PackagePreparationStatus.preparing),
        isTrue,
      );
      expect(
        PackagePreparationTransitions.canTransition(
            PackagePreparationStatus.exception,
            PackagePreparationStatus.packed),
        isFalse,
      );
    });

    test('delivered and cancelled are terminal', () {
      expect(
          PackagePreparationTransitions.isTerminal(
              PackagePreparationStatus.delivered),
          isTrue);
      expect(
          PackagePreparationTransitions.isTerminal(
              PackagePreparationStatus.cancelled),
          isTrue);
    });
  });
}
