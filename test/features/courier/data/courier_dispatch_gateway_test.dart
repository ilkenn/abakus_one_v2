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

    test('registerConsortiumOrder fails closed', () async {
      await expectLater(
        gateway.registerConsortiumOrder(
          organizationId: 'org-1',
          branchId: 'branch-1',
          merchantId: 'merchant-a',
          merchantName: 'Dış Restoran A',
          pickupAddress: 'Test address',
          consortiumDeliveryFeeMinorUnits: 5000,
          contactFirstName: 'Ada',
          contactLastName: 'Yılmaz',
          contactPhone: '+905551112233',
          dropoffAddressDescription: 'Test dropoff',
        ),
        throwsA(isA<CourierDispatchException>()),
      );
    });

    test('batchAssignCourierToOrders fails closed', () async {
      await expectLater(
        gateway.batchAssignCourierToOrders(
          orderIds: const ['order-1', 'order-2'],
          courierId: 'courier-1',
        ),
        throwsA(isA<CourierDispatchException>()),
      );
    });
  });
}
