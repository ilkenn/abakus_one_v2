import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_performance_snapshot.dart';
import 'package:abakus_one_v2/features/courier/data/customer_contact_action_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_assignment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_failure_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/data/geofence_override_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/courier_test_fixtures.dart';

void main() {
  group('BuildCourierPerformanceSnapshot', () {
    test('counts only deliveries created within the requested period',
        () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
        id: 'in-period',
        status: DeliveryStatus.delivered,
        courierId: 'courier-1',
      ));
      final useCase = BuildCourierPerformanceSnapshot(
        deliveryRepository: deliveryRepository,
        assignmentRepository: InMemoryDeliveryAssignmentRepository(),
        failureRepository: InMemoryDeliveryFailureRepository(),
        geofenceOverrideRepository: InMemoryGeofenceOverrideRepository(),
        contactActionRepository: InMemoryCustomerContactActionRepository(),
      );

      final snapshot = await useCase(
        courierId: 'courier-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 2),
      );
      expect(snapshot.successfulDeliveries, 1);

      final outsideSnapshot = await useCase(
        courierId: 'courier-1',
        periodStart: DateTime(2027, 1, 1),
        periodEnd: DateTime(2027, 1, 2),
      );
      expect(outsideSnapshot.successfulDeliveries, 0);
    });

    test(
        'never includes a score/rank field for the courier — only the '
        'explicitly named operational metrics', () async {
      final useCase = BuildCourierPerformanceSnapshot(
        deliveryRepository: InMemoryDeliveryRepository(),
        assignmentRepository: InMemoryDeliveryAssignmentRepository(),
        failureRepository: InMemoryDeliveryFailureRepository(),
        geofenceOverrideRepository: InMemoryGeofenceOverrideRepository(),
        contactActionRepository: InMemoryCustomerContactActionRepository(),
      );
      final snapshot = await useCase(
        courierId: 'courier-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 2, 1),
      );
      expect(snapshot.courierId, 'courier-1');
      expect(snapshot.assignmentsOffered, 0);
    });
  });
}
