import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/identity/customer_contact_action_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_failure_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_feedback_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/record_courier_feedback.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/record_customer_contact_action.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/record_delivery_failure.dart';
import 'package:abakus_one_v2/features/courier/data/courier_feedback_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/customer_contact_action_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_failure_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/contact/customer_contact_action_type.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_failure_reason.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_failure_responsibility.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

void main() {
  group('RecordDeliveryFailure', () {
    test(
        'a customer-caused reason moves the delivery to deliveryFailed '
        'and mayEmitCustomerRiskSignal is true', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository
          .save(buildTestDelivery(status: DeliveryStatus.enRoute));
      final useCase = RecordDeliveryFailure(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialDeliveryFailureIdGenerator(),
        deliveryRepository: deliveryRepository,
        failureRepository: InMemoryDeliveryFailureRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final failure = await useCase(
        deliveryId: 'delivery-1',
        reasonCode: DeliveryFailureReason.customerUnavailable,
        performedByStaffId: 'courier-1',
      );
      expect(failure.responsibility, DeliveryFailureResponsibility.customer);
      expect(failure.mayEmitCustomerRiskSignal, isTrue);
      final delivery = await deliveryRepository.findById('delivery-1');
      expect(delivery!.status, DeliveryStatus.deliveryFailed);
    });

    test(
        'a restaurant-caused failure at the pickup stage moves the '
        'delivery to pickupFailed, never deliveryFailed, and never emits a '
        'customer-risk signal', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository
          .save(buildTestDelivery(status: DeliveryStatus.arrivedAtRestaurant));
      final useCase = RecordDeliveryFailure(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialDeliveryFailureIdGenerator(),
        deliveryRepository: deliveryRepository,
        failureRepository: InMemoryDeliveryFailureRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final failure = await useCase(
        deliveryId: 'delivery-1',
        reasonCode: DeliveryFailureReason.packageProblem,
        performedByStaffId: 'courier-1',
      );
      expect(failure.responsibility, DeliveryFailureResponsibility.restaurant);
      expect(failure.mayEmitCustomerRiskSignal, isFalse);
      final delivery = await deliveryRepository.findById('delivery-1');
      expect(delivery!.status, DeliveryStatus.pickupFailed);
    });

    test('courierNote is truncated to 280 characters', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository
          .save(buildTestDelivery(status: DeliveryStatus.enRoute));
      final useCase = RecordDeliveryFailure(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialDeliveryFailureIdGenerator(),
        deliveryRepository: deliveryRepository,
        failureRepository: InMemoryDeliveryFailureRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
        recordCourierEvent: buildTestRecordCourierEvent(),
      );
      final longNote = 'a' * 400;
      final failure = await useCase(
        deliveryId: 'delivery-1',
        reasonCode: DeliveryFailureReason.customerUnavailable,
        courierNote: longNote,
        performedByStaffId: 'courier-1',
      );
      expect(failure.courierNote.length, 280);
    });
  });

  group('RecordCustomerContactAction', () {
    test(
        'access is limited to the active delivery window — blocked once '
        'delivered', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
          status: DeliveryStatus.delivered, courierId: 'courier-1'));
      final useCase = RecordCustomerContactAction(
        clock: FakeClock(DateTime(2026, 1, 1)),
        idGenerator: SequentialCustomerContactActionIdGenerator(),
        deliveryRepository: deliveryRepository,
        actionRepository: InMemoryCustomerContactActionRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      expect(
        () => useCase(
          deliveryId: 'delivery-1',
          courierId: 'courier-1',
          type: CustomerContactActionType.maskedCall,
          performedByStaffId: 'courier-1',
        ),
        throwsA(isA<InvalidDeliveryTransitionViolation>()),
      );
    });

    test(
        'never carries raw customer contact data — only an operational '
        'note reaches the record', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
          status: DeliveryStatus.enRoute, courierId: 'courier-1'));
      final actionRepository = InMemoryCustomerContactActionRepository();
      final useCase = RecordCustomerContactAction(
        clock: FakeClock(DateTime(2026, 1, 1)),
        idGenerator: SequentialCustomerContactActionIdGenerator(),
        deliveryRepository: deliveryRepository,
        actionRepository: actionRepository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final action = await useCase(
        deliveryId: 'delivery-1',
        courierId: 'courier-1',
        type: CustomerContactActionType.maskedCall,
        loggedNote: 'no answer',
        performedByStaffId: 'courier-1',
      );
      expect(action.loggedNote, 'no answer');
      // CustomerContactAction has no field capable of holding a phone
      // number/address at all — structurally enforced, not just by
      // convention.
    });
  });

  group('RecordCourierFeedback', () {
    test('requires at least one predefined tag', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery());
      final useCase = RecordCourierFeedback(
        clock: FakeClock(DateTime(2026, 1, 1)),
        idGenerator: SequentialCourierFeedbackIdGenerator(),
        deliveryRepository: deliveryRepository,
        feedbackRepository: InMemoryCourierFeedbackRepository(),
      );
      expect(
        () => useCase(
          deliveryId: 'delivery-1',
          courierId: 'courier-1',
          tags: [],
        ),
        throwsA(isA<InvalidCourierFeedbackViolation>()),
      );
    });
  });
}
