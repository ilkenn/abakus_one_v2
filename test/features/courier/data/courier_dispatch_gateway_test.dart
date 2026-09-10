import 'package:abakus_one_v2/features/courier/data/courier_dispatch_gateway.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UnavailableCourierDispatchGateway', () {
    const gateway = UnavailableCourierDispatchGateway();

    test('setCourier fails closed', () async {
      await expectLater(
        gateway.setCourier(
          organizationId: 'org-1',
          branchId: 'branch-1',
          displayName: 'Ali',
          phoneNumber: '+905551112233',
        ),
        throwsA(isA<CourierDispatchException>()),
      );
    });

    test('assignCourierToOrder fails closed', () async {
      await expectLater(
        gateway.assignCourierToOrder(orderId: 'order-1', courierId: 'courier-1'),
        throwsA(isA<CourierDispatchException>()),
      );
    });

    test('markCourierReturned fails closed', () async {
      await expectLater(
        gateway.markCourierReturned(courierId: 'courier-1'),
        throwsA(isA<CourierDispatchException>()),
      );
    });
  });
}
