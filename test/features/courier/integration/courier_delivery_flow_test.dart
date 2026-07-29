import 'package:abakus_one_v2/features/courier/application/identity/delivery_assignment_attempt_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_assignment_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_proof_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/complete_delivery.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/confirm_package_pickup.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/create_delivery.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/declare_courier_cash_collection_for_delivery.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/mark_delivery_ready_for_assignment.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/offer_delivery_assignment.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/respond_to_delivery_assignment.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/transition_delivery.dart';
import 'package:abakus_one_v2/features/courier/data/courier_availability_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_assignment_attempt_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_assignment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_proof_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_proof_type.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/courier/domain/dispatch/dispatch_scoring_input.dart';
import 'package:abakus_one_v2/features/orders/data/package_preparation_repository.dart';
import 'package:abakus_one_v2/features/orders/domain/fulfillment/package_preparation.dart';
import 'package:abakus_one_v2/features/orders/domain/fulfillment/package_preparation_status.dart';
import 'package:abakus_one_v2/features/orders/domain/models/order_id.dart';
import 'package:abakus_one_v2/features/pos/application/identity/courier_cash_collection_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/identity/courier_settlement_session_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/advance_package_preparation.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/open_courier_settlement_session.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/record_courier_cash_collection.dart'
    as pos;
import 'package:abakus_one_v2/features/pos/data/courier_cash_collection_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/pos/data/courier_settlement_session_repository.dart';
import 'package:abakus_one_v2/features/pos/data/payment_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/features/pos/domain/courier_settlement/courier_collection_type.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session.dart';
import 'package:abakus_one_v2/features/pos/domain/models/payment_session_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

void main() {
  test(
      'PackagePreparation -> readyForAssignment -> automatic dispatch -> '
      'accept -> restaurant arrival -> pickup -> en route -> customer '
      'arrival -> complete -> cash collection, end to end', () async {
    const orderId = 'order-42';
    const branchId = 'branch-1';
    const courierId = 'courier-1';
    final clock = FakeClock(DateTime(2026, 1, 1, 12));
    final authorizationPolicy =
        FakePosAuthorizationPolicy(const AuthorizationResult(granted: true));

    // --- Shared in-memory infrastructure. ---
    final deliveryRepository = InMemoryDeliveryRepository();
    final assignmentRepository = InMemoryDeliveryAssignmentRepository();
    final attemptRepository = InMemoryDeliveryAssignmentAttemptRepository();
    final availabilityRepository = InMemoryCourierAvailabilityRepository();
    final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
    final proofRepository = InMemoryDeliveryProofRepository();
    final packageRepository = InMemoryPackagePreparationRepository();

    await availabilityRepository.save(
        buildTestAvailability(courierId: courierId, activeAssignmentCount: 0));

    // --- orders/Sprint 3D: package preparation reaches waitingForCourier.
    await packageRepository.save(PackagePreparation(
      orderId: OrderId(orderId),
      status: PackagePreparationStatus.preparing,
      revision: 1,
    ));
    final advancePackage =
        AdvancePackagePreparation(repository: packageRepository);
    for (final status in [
      PackagePreparationStatus.readyForPacking,
      PackagePreparationStatus.packing,
      PackagePreparationStatus.packed,
      PackagePreparationStatus.waitingForCourier,
    ]) {
      final current =
          await packageRepository.findCurrentByOrderId(OrderId(orderId));
      await advancePackage(
        orderId: OrderId(orderId),
        newStatus: status,
        performedByStaffId: 'kitchen-1',
        at: clock.now(),
      );
      expect(
          (await packageRepository.findCurrentByOrderId(OrderId(orderId)))!
              .status,
          status);
      expect(current, isNotNull);
    }

    // --- Phase 5E: create the Delivery aggregate. ---
    final createDelivery = CreateDelivery(
      clock: clock,
      idGenerator: SequentialDeliveryIdGenerator(),
      repository: deliveryRepository,
    );
    final created =
        await createDelivery(orderId: OrderId(orderId), branchId: branchId);
    expect(created.status, DeliveryStatus.awaitingPackage);

    final readyForAssignment = await MarkDeliveryReadyForAssignment(
        repository: deliveryRepository)(deliveryId: created.id);
    expect(readyForAssignment.status, DeliveryStatus.readyForAssignment);

    // --- Phase 5G: automatic dispatch offers to the sole eligible courier.
    final offer = OfferDeliveryAssignment(
      clock: clock,
      authorizationPolicy: authorizationPolicy,
      assignmentIdGenerator: SequentialDeliveryAssignmentIdGenerator(),
      attemptIdGenerator: SequentialDeliveryAssignmentAttemptIdGenerator(),
      deliveryRepository: deliveryRepository,
      assignmentRepository: assignmentRepository,
      attemptRepository: attemptRepository,
      auditRepository: auditRepository,
      recordCourierEvent: buildTestRecordCourierEvent(),
    );
    final assignment = await offer(
      deliveryId: created.id,
      expectedRevision: readyForAssignment.revision,
      candidates: [
        const DispatchScoringInput(
          courierId: courierId,
          isAvailable: true,
          isEligibleForBranch: true,
          activeDeliveryCount: 0,
          capacity: 3,
          distanceEstimateMeters: 300,
          packageWaitSeconds: 60,
          recentRejectionCount: 0,
        ),
      ],
      performedByStaffId: 'system',
    );
    expect(assignment.courierId, courierId);

    // --- Courier accepts. ---
    final respond = RespondToDeliveryAssignment(
      clock: clock,
      authorizationPolicy: authorizationPolicy,
      assignmentRepository: assignmentRepository,
      deliveryRepository: deliveryRepository,
      availabilityRepository: availabilityRepository,
      auditRepository: auditRepository,
      recordCourierEvent: buildTestRecordCourierEvent(),
    );
    await respond(
      assignmentId: assignment.id,
      courierId: courierId,
      accept: true,
      performedByStaffId: courierId,
    );
    final accepted = await deliveryRepository.findById(created.id);
    expect(accepted!.status, DeliveryStatus.accepted);
    final availabilityAfterAccept =
        await availabilityRepository.findByCourierId(courierId);
    expect(availabilityAfterAccept!.activeAssignmentCount, 1);

    // --- Restaurant arrival (no geofence reading supplied — skips the
    // check, matching TransitionDelivery's own documented behavior). ---
    final transition = TransitionDelivery(
      clock: clock,
      authorizationPolicy: authorizationPolicy,
      repository: deliveryRepository,
      auditRepository: auditRepository,
      recordCourierEvent: buildTestRecordCourierEvent(),
    );
    final arrived = await transition(
      deliveryId: created.id,
      to: DeliveryStatus.arrivedAtRestaurant,
      expectedRevision: accepted.revision,
      performedByStaffId: courierId,
    );

    // --- Phase 5F: pickup, bridging into PackagePreparation. ---
    final confirmPickup = ConfirmPackagePickup(
      clock: clock,
      authorizationPolicy: authorizationPolicy,
      repository: deliveryRepository,
      auditRepository: auditRepository,
      recordCourierEvent: buildTestRecordCourierEvent(),
      isPackageReadyForPickup: ({required orderId}) async {
        final current = await packageRepository.findCurrentByOrderId(orderId);
        return current?.status == PackagePreparationStatus.waitingForCourier;
      },
      advanceToCourierCollected: (
          {required orderId, required performedByStaffId, required at}) async {
        await advancePackage(
          orderId: orderId,
          newStatus: PackagePreparationStatus.courierCollected,
          performedByStaffId: performedByStaffId,
          at: at,
        );
      },
    );
    final pickedUp = await confirmPickup(
      deliveryId: created.id,
      performedByStaffId: courierId,
    );
    expect(pickedUp.status, DeliveryStatus.pickedUp);
    expect(
      (await packageRepository.findCurrentByOrderId(OrderId(orderId)))!.status,
      PackagePreparationStatus.courierCollected,
    );
    expect(arrived.status, DeliveryStatus.arrivedAtRestaurant);

    // --- En route -> customer arrival. ---
    final enRoute = await transition(
      deliveryId: created.id,
      to: DeliveryStatus.enRoute,
      expectedRevision: pickedUp.revision,
      performedByStaffId: courierId,
    );
    final atCustomer = await transition(
      deliveryId: created.id,
      to: DeliveryStatus.arrivedAtCustomer,
      expectedRevision: enRoute.revision,
      performedByStaffId: courierId,
    );

    // --- Phase 5J: completion, walking PackagePreparation the rest of the
    // way to delivered. ---
    final complete = CompleteDelivery(
      clock: clock,
      authorizationPolicy: authorizationPolicy,
      repository: deliveryRepository,
      proofIdGenerator: SequentialDeliveryProofIdGenerator(),
      proofRepository: proofRepository,
      auditRepository: auditRepository,
      recordCourierEvent: buildTestRecordCourierEvent(),
      advanceToDelivered: ({
        required orderId,
        required performedByStaffId,
        required at,
      }) async {
        await advancePackage(
          orderId: orderId,
          newStatus: PackagePreparationStatus.outForDelivery,
          performedByStaffId: performedByStaffId,
          at: at,
        );
        await advancePackage(
          orderId: orderId,
          newStatus: PackagePreparationStatus.delivered,
          performedByStaffId: performedByStaffId,
          at: at,
        );
      },
    );
    final delivered = await complete(
      deliveryId: created.id,
      courierId: courierId,
      expectedRevision: atCustomer.revision,
      performedByStaffId: courierId,
      proofType: DeliveryProofType.courierConfirmation,
    );
    expect(delivered.status, DeliveryStatus.delivered);
    expect(
      (await packageRepository.findCurrentByOrderId(OrderId(orderId)))!.status,
      PackagePreparationStatus.delivered,
    );
    final proofs = await proofRepository.findByDeliveryId(created.id);
    expect(proofs, hasLength(1));

    // --- Sprint 3F: cash-on-delivery collection — declared by the
    // courier, never duplicating a PaymentSession. ---
    final settlementSessionRepository =
        InMemoryCourierSettlementSessionRepository();
    final paymentSessionRepository = InMemoryPaymentSessionRepository();
    final collectionRepository = InMemoryCourierCashCollectionRepository();
    final settlementAuditRepository =
        InMemoryCourierSettlementAuditEntryRepository();

    final session = await OpenCourierSettlementSession(
      clock: clock,
      idGenerator: SequentialCourierSettlementSessionIdGenerator(),
      sessionRepository: settlementSessionRepository,
    )(courierId: courierId, branchId: branchId);

    await paymentSessionRepository.save(PaymentSession(
      id: 'payment-session-1',
      orderId: OrderId(orderId),
      totalAmount: Money.fromWhole(150, Currency.tryLira),
      status: PaymentSessionStatus.completed,
      createdAt: clock.now(),
      revision: 1,
    ));

    final declareCollection = DeclareCourierCashCollectionForDelivery(
      recordCourierCashCollection: pos.RecordCourierCashCollection(
        clock: clock,
        idGenerator: SequentialCourierCashCollectionIdGenerator(),
        sessionRepository: settlementSessionRepository,
        paymentSessionRepository: paymentSessionRepository,
        collectionRepository: collectionRepository,
        auditRepository: settlementAuditRepository,
      ),
      deliveryRepository: deliveryRepository,
    );
    final collection = await declareCollection(
      deliveryId: created.id,
      settlementSessionId: session.id,
      paymentSessionId: 'payment-session-1',
      collectedAmount: Money.fromWhole(150, Currency.tryLira),
      collectionType: CourierCollectionType.full,
    );
    expect(collection.orderId, OrderId(orderId));
    expect(collection.settlementSessionId, session.id);

    // --- Final assertions: every layer's own state is consistent, and no
    // layer duplicated another's data. ---
    final finalDelivery = await deliveryRepository.findById(created.id);
    expect(finalDelivery!.isTerminal, isTrue);
    final auditEntries = await auditRepository.findByDeliveryId(created.id);
    expect(auditEntries, isNotEmpty);
  });
}
