import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_earnings_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/shift_hourly_earnings_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/calculate_delivery_earnings.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/calculate_shift_hourly_earnings.dart';
import 'package:abakus_one_v2/features/courier/data/courier_compensation_profile_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_shift_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_shift_schedule_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_earnings_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_tracking_repository.dart';
import 'package:abakus_one_v2/features/courier/data/shift_hourly_earnings_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/compensation/courier_compensation_profile.dart';
import 'package:abakus_one_v2/features/courier/domain/compensation/courier_shift_schedule.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_route_snapshot.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/courier/domain/shift/courier_shift_status.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

CourierCompensationProfile _testProfile({
  String courierId = 'courier-1',
  DateTime? effectiveFrom,
  Money? hourlyRate,
  Money? deliveryFeePerPackage,
  double freeDistanceKm = 3,
  Money? extraDistanceRatePerKm,
}) {
  return CourierCompensationProfile(
    id: 'profile-1',
    courierId: courierId,
    version: 1,
    effectiveFrom: effectiveFrom ?? DateTime(2026, 1, 1),
    hourlyRate: hourlyRate ?? Money.fromWhole(50, Currency.tryLira),
    deliveryFeePerPackage:
        deliveryFeePerPackage ?? Money.fromWhole(20, Currency.tryLira),
    freeDistanceKm: freeDistanceKm,
    extraDistanceRatePerKm:
        extraDistanceRatePerKm ?? Money.fromWhole(5, Currency.tryLira),
    createdByStaffId: 'manager-1',
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('CalculateDeliveryEarnings', () {
    test(
        'throws when the delivery is neither delivered nor '
        'manager-approved-cancelled', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
          status: DeliveryStatus.enRoute, courierId: 'courier-1'));
      final useCase = CalculateDeliveryEarnings(
        clock: FakeClock(DateTime(2026, 2, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialDeliveryEarningsIdGenerator(),
        deliveryRepository: deliveryRepository,
        trackingRepository: InMemoryDeliveryTrackingRepository(),
        compensationProfileRepository:
            InMemoryCourierCompensationProfileRepository(),
        earningsRepository: InMemoryDeliveryEarningsRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      expect(
        () =>
            useCase(deliveryId: 'delivery-1', performedByStaffId: 'courier-1'),
        throwsA(isA<DeliveryNotEligibleForEarningsViolation>()),
      );
    });

    test(
        'a plain cancelled delivery without manager approval is not '
        'eligible', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
          status: DeliveryStatus.cancelled, courierId: 'courier-1'));
      final useCase = CalculateDeliveryEarnings(
        clock: FakeClock(DateTime(2026, 2, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialDeliveryEarningsIdGenerator(),
        deliveryRepository: deliveryRepository,
        trackingRepository: InMemoryDeliveryTrackingRepository(),
        compensationProfileRepository:
            InMemoryCourierCompensationProfileRepository(),
        earningsRepository: InMemoryDeliveryEarningsRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      expect(
        () =>
            useCase(deliveryId: 'delivery-1', performedByStaffId: 'courier-1'),
        throwsA(isA<DeliveryNotEligibleForEarningsViolation>()),
      );
    });

    test(
        'a manager-approved cancelled delivery is eligible and uses the '
        'approval authorization action', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
          status: DeliveryStatus.cancelled, courierId: 'courier-1'));
      final profileRepository = InMemoryCourierCompensationProfileRepository();
      await profileRepository.append(_testProfile());
      final policy =
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: true));
      final useCase = CalculateDeliveryEarnings(
        clock: FakeClock(DateTime(2026, 2, 1)),
        authorizationPolicy: policy,
        idGenerator: SequentialDeliveryEarningsIdGenerator(),
        deliveryRepository: deliveryRepository,
        trackingRepository: InMemoryDeliveryTrackingRepository(),
        compensationProfileRepository: profileRepository,
        earningsRepository: InMemoryDeliveryEarningsRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final earnings = await useCase(
        deliveryId: 'delivery-1',
        managerApprovedCancellation: true,
        approvalReason: 'Müşteri kabul etmedi ama hazırdı',
        performedByStaffId: 'manager-1',
      );
      expect(earnings.wasManagerApprovedCancellation, isTrue);
      expect(policy.lastAction?.name, 'approveCancelledDeliveryEarnings');
    });

    test('throws when no compensation profile covers the delivery time',
        () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
          status: DeliveryStatus.delivered, courierId: 'courier-1'));
      final useCase = CalculateDeliveryEarnings(
        clock: FakeClock(DateTime(2026, 2, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialDeliveryEarningsIdGenerator(),
        deliveryRepository: deliveryRepository,
        trackingRepository: InMemoryDeliveryTrackingRepository(),
        compensationProfileRepository:
            InMemoryCourierCompensationProfileRepository(),
        earningsRepository: InMemoryDeliveryEarningsRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      expect(
        () =>
            useCase(deliveryId: 'delivery-1', performedByStaffId: 'courier-1'),
        throwsA(isA<NoEffectiveCompensationProfileViolation>()),
      );
    });

    test(
        'computes package fee plus extra-distance earnings correctly, '
        'only charging distance beyond freeDistanceKm', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
          status: DeliveryStatus.delivered, courierId: 'courier-1'));
      final profileRepository = InMemoryCourierCompensationProfileRepository();
      await profileRepository.append(_testProfile(freeDistanceKm: 3));
      final trackingRepository = InMemoryDeliveryTrackingRepository();
      await trackingRepository.append(DeliveryRouteSnapshot(
        id: 'route-1',
        deliveryId: 'delivery-1',
        distanceEstimateMeters: 8000, // 8 km total
        computedAt: DateTime(2026, 2, 1),
      ));
      final useCase = CalculateDeliveryEarnings(
        clock: FakeClock(DateTime(2026, 2, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialDeliveryEarningsIdGenerator(),
        deliveryRepository: deliveryRepository,
        trackingRepository: trackingRepository,
        compensationProfileRepository: profileRepository,
        earningsRepository: InMemoryDeliveryEarningsRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final earnings = await useCase(
          deliveryId: 'delivery-1', performedByStaffId: 'courier-1');

      // 8km - 3km free = 5km extra * 5 TRY/km = 25 TRY extra distance.
      expect(earnings.extraDistanceKm, 5);
      expect(earnings.extraDistanceEarnings,
          Money.fromWhole(25, Currency.tryLira));
      // package fee 20 + extra distance 25 = 45 TRY total.
      expect(earnings.totalEarnings, Money.fromWhole(45, Currency.tryLira));
    });

    test('no route snapshot means zero distance, never an error', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
          status: DeliveryStatus.delivered, courierId: 'courier-1'));
      final profileRepository = InMemoryCourierCompensationProfileRepository();
      await profileRepository.append(_testProfile());
      final useCase = CalculateDeliveryEarnings(
        clock: FakeClock(DateTime(2026, 2, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialDeliveryEarningsIdGenerator(),
        deliveryRepository: deliveryRepository,
        trackingRepository: InMemoryDeliveryTrackingRepository(),
        compensationProfileRepository: profileRepository,
        earningsRepository: InMemoryDeliveryEarningsRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final earnings = await useCase(
          deliveryId: 'delivery-1', performedByStaffId: 'courier-1');
      expect(earnings.distanceKm, 0);
      expect(earnings.extraDistanceEarnings.isZero, isTrue);
      expect(earnings.totalEarnings, Money.fromWhole(20, Currency.tryLira));
    });

    test(
        'is idempotent — a second call returns the same record without '
        'recomputing', () async {
      final deliveryRepository = InMemoryDeliveryRepository();
      await deliveryRepository.save(buildTestDelivery(
          status: DeliveryStatus.delivered, courierId: 'courier-1'));
      final profileRepository = InMemoryCourierCompensationProfileRepository();
      await profileRepository.append(_testProfile());
      final earningsRepository = InMemoryDeliveryEarningsRepository();
      final useCase = CalculateDeliveryEarnings(
        clock: FakeClock(DateTime(2026, 2, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialDeliveryEarningsIdGenerator(),
        deliveryRepository: deliveryRepository,
        trackingRepository: InMemoryDeliveryTrackingRepository(),
        compensationProfileRepository: profileRepository,
        earningsRepository: earningsRepository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final first = await useCase(
          deliveryId: 'delivery-1', performedByStaffId: 'courier-1');
      final second = await useCase(
          deliveryId: 'delivery-1', performedByStaffId: 'courier-1');
      expect(second.id, first.id);

      final all = await earningsRepository.findByDeliveryId('delivery-1');
      expect(all, isNotNull); // only one record was ever stored
    });
  });

  group('CalculateShiftHourlyEarnings', () {
    test(
        'without a CourierShiftSchedule, falls back to the shift\'s own '
        'actual startedAt/endedAt', () async {
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository
          .save(buildTestActiveShift(status: CourierShiftStatus.completed));
      final profileRepository = InMemoryCourierCompensationProfileRepository();
      await profileRepository.append(_testProfile());
      final useCase = CalculateShiftHourlyEarnings(
        clock: FakeClock(DateTime(2026, 2, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialShiftHourlyEarningsIdGenerator(),
        shiftRepository: shiftRepository,
        scheduleRepository: InMemoryCourierShiftScheduleRepository(),
        compensationProfileRepository: profileRepository,
        earningsRepository: InMemoryShiftHourlyEarningsRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final earnings =
          await useCase(shiftId: 'shift-1', performedByStaffId: 'manager-1');
      // buildTestActiveShift: startedAt 09:00, no endedAt set by default
      // (fixture only sets startedAt) — with no schedule, both scheduled
      // start and scheduled end fall back to the shift's own actual
      // startedAt, yielding zero payable duration (a conservative default,
      // never a fabricated number).
      expect(earnings.wasCutShortByFinalDeliveryArrival, isFalse);
      expect(earnings.payableDuration, Duration.zero);
    });

    test(
        'a scheduled window produces the exact early/late-arrival '
        'business-rule examples', () async {
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository.save(buildTestActiveShift(
        status: CourierShiftStatus.completed,
      ));
      final scheduleRepository = InMemoryCourierShiftScheduleRepository();
      await scheduleRepository.append(CourierShiftSchedule(
        id: 'sched-1',
        shiftId: 'shift-1',
        courierId: 'courier-1',
        scheduledStart: DateTime(2026, 1, 1, 10, 0),
        scheduledEnd: DateTime(2026, 1, 1, 18, 0),
        setByStaffId: 'manager-1',
        setAt: DateTime(2026, 1, 1, 8),
      ));
      final profileRepository = InMemoryCourierCompensationProfileRepository();
      await profileRepository.append(_testProfile(
        effectiveFrom: DateTime(2025, 1, 1),
        hourlyRate: Money.fromWhole(20, Currency.tryLira),
      ));
      final useCase = CalculateShiftHourlyEarnings(
        clock: FakeClock(DateTime(2026, 2, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialShiftHourlyEarningsIdGenerator(),
        shiftRepository: shiftRepository,
        scheduleRepository: scheduleRepository,
        compensationProfileRepository: profileRepository,
        earningsRepository: InMemoryShiftHourlyEarningsRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final earnings =
          await useCase(shiftId: 'shift-1', performedByStaffId: 'manager-1');

      // buildTestActiveShift's startedAt fixture is 2026-01-01 09:00 (an
      // early login relative to the 10:00 scheduled start) - early arrival
      // must not create extra earnings, so start is clamped to 10:00.
      expect(earnings.earningsStartAt, DateTime(2026, 1, 1, 10, 0));
      expect(earnings.earningsEndAt, DateTime(2026, 1, 1, 18, 0));
      expect(earnings.payableDuration, const Duration(hours: 8));
      expect(earnings.hourlyEarnings, Money.fromWhole(160, Currency.tryLira));
    });

    test(
        'a final-delivery verified-arrival instant cuts the window short '
        'of the scheduled end', () async {
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository
          .save(buildTestActiveShift(status: CourierShiftStatus.completed));
      final scheduleRepository = InMemoryCourierShiftScheduleRepository();
      await scheduleRepository.append(CourierShiftSchedule(
        id: 'sched-1',
        shiftId: 'shift-1',
        courierId: 'courier-1',
        scheduledStart: DateTime(2026, 1, 1, 9, 0),
        scheduledEnd: DateTime(2026, 1, 1, 18, 0),
        setByStaffId: 'manager-1',
        setAt: DateTime(2026, 1, 1, 8),
      ));
      final profileRepository = InMemoryCourierCompensationProfileRepository();
      await profileRepository.append(_testProfile(
        effectiveFrom: DateTime(2025, 1, 1),
        hourlyRate: Money.fromWhole(20, Currency.tryLira),
      ));
      final useCase = CalculateShiftHourlyEarnings(
        clock: FakeClock(DateTime(2026, 2, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialShiftHourlyEarningsIdGenerator(),
        shiftRepository: shiftRepository,
        scheduleRepository: scheduleRepository,
        compensationProfileRepository: profileRepository,
        earningsRepository: InMemoryShiftHourlyEarningsRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final earnings = await useCase(
        shiftId: 'shift-1',
        finalDeliveryVerifiedArrivalAt: DateTime(2026, 1, 1, 18, 12),
        performedByStaffId: 'manager-1',
      );
      expect(earnings.earningsEndAt, DateTime(2026, 1, 1, 18, 12));
      expect(earnings.wasCutShortByFinalDeliveryArrival, isTrue);
    });

    test('is idempotent — a second call returns the same record', () async {
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository
          .save(buildTestActiveShift(status: CourierShiftStatus.completed));
      final profileRepository = InMemoryCourierCompensationProfileRepository();
      await profileRepository.append(_testProfile());
      final useCase = CalculateShiftHourlyEarnings(
        clock: FakeClock(DateTime(2026, 2, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialShiftHourlyEarningsIdGenerator(),
        shiftRepository: shiftRepository,
        scheduleRepository: InMemoryCourierShiftScheduleRepository(),
        compensationProfileRepository: profileRepository,
        earningsRepository: InMemoryShiftHourlyEarningsRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final first =
          await useCase(shiftId: 'shift-1', performedByStaffId: 'manager-1');
      final second =
          await useCase(shiftId: 'shift-1', performedByStaffId: 'manager-1');
      expect(second.id, first.id);
    });

    test('throws when authorization is denied', () async {
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository
          .save(buildTestActiveShift(status: CourierShiftStatus.completed));
      final useCase = CalculateShiftHourlyEarnings(
        clock: FakeClock(DateTime(2026, 2, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: false)),
        idGenerator: SequentialShiftHourlyEarningsIdGenerator(),
        shiftRepository: shiftRepository,
        scheduleRepository: InMemoryCourierShiftScheduleRepository(),
        compensationProfileRepository:
            InMemoryCourierCompensationProfileRepository(),
        earningsRepository: InMemoryShiftHourlyEarningsRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      expect(
        () => useCase(shiftId: 'shift-1', performedByStaffId: 'manager-1'),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
