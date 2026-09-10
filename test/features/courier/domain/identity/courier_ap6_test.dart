import 'package:abakus_one_v2/features/courier/domain/identity/courier.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier_registry_status.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier_status.dart';
import 'package:abakus_one_v2/features/courier/domain/identity/courier_vehicle_type.dart';
import 'package:abakus_one_v2/shared/models/courier_type.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Courier AP-6 Sprint 2 fields', () {
    test('every AP-6 field defaults sensibly when omitted', () {
      final courier = Courier(
        id: 'c1',
        primaryBranchId: 'branch-1',
        displayName: 'Ali',
        phoneNumber: '+905551112233',
        registeredAt: DateTime(2026, 1, 1),
      );

      expect(courier.type, CourierType.internal);
      expect(courier.dispatchStatus, CourierStatus.offline);
      expect(courier.returnedAt, isNull);
      expect(courier.activeOrderIds, isEmpty);
      // Relaxed-to-optional fields (AP-6) still default sensibly for
      // every pre-existing caller that omits them.
      expect(courier.vehicleType, CourierVehicleType.motorcycle);
      expect(courier.capacity, 1);
      expect(courier.status, CourierRegistryStatus.active);
    });

    test('every existing required-field caller shape still compiles and holds explicit values', () {
      final courier = Courier(
        id: 'c1',
        primaryBranchId: 'branch-1',
        displayName: 'Ali',
        phoneNumber: '+905551112233',
        vehicleType: CourierVehicleType.bicycle,
        capacity: 3,
        registeredAt: DateTime(2026, 1, 1),
      );

      expect(courier.vehicleType, CourierVehicleType.bicycle);
      expect(courier.capacity, 3);
    });

    test('copyWith updates AP-6 fields independently of the rest', () {
      final original = Courier(
        id: 'c1',
        primaryBranchId: 'branch-1',
        displayName: 'Ali',
        phoneNumber: '+905551112233',
        registeredAt: DateTime(2026, 1, 1),
        type: CourierType.internal,
        dispatchStatus: CourierStatus.offline,
      );

      final updated = original.copyWith(
        dispatchStatus: CourierStatus.delivering,
        activeOrderIds: ['order-1'],
      );

      expect(updated.dispatchStatus, CourierStatus.delivering);
      expect(updated.activeOrderIds, ['order-1']);
      expect(updated.type, CourierType.internal);
      expect(updated.displayName, 'Ali');
    });
  });
}
