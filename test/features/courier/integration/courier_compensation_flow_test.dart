import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_compensation_profile_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_earnings_adjustment_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_earnings_payment_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_shift_schedule_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/delivery_earnings_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/shift_hourly_earnings_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/build_courier_earnings_summary.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/calculate_delivery_earnings.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/calculate_shift_hourly_earnings.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/create_courier_compensation_profile.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/create_courier_earnings_adjustment.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/mark_courier_earnings_paid.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/schedule_courier_shift.dart';
import 'package:abakus_one_v2/features/courier/data/courier_compensation_profile_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_earnings_adjustment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_earnings_payment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_shift_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_shift_schedule_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_earnings_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_repository.dart';
import 'package:abakus_one_v2/features/courier/data/delivery_tracking_repository.dart';
import 'package:abakus_one_v2/features/courier/data/shift_hourly_earnings_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_route_snapshot.dart';
import 'package:abakus_one_v2/features/courier/domain/delivery/delivery_status.dart';
import 'package:abakus_one_v2/features/courier/domain/shift/courier_shift_status.dart';
import 'package:abakus_one_v2/features/courier/domain/compensation/courier_earnings_adjustment_reason.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

void main() {
  test(
      'compensation profile -> delivery earnings -> shift earnings -> '
      'manager adjustment -> summary -> mark paid -> double-pay rejected, '
      'end to end', () async {
    const courierId = 'courier-1';
    const branchId = 'branch-1';
    final clock = FakeClock(DateTime(2026, 1, 1, 20));
    final policy =
        FakePosAuthorizationPolicy(const AuthorizationResult(granted: true));

    final profileRepository = InMemoryCourierCompensationProfileRepository();
    final deliveryRepository = InMemoryDeliveryRepository();
    final trackingRepository = InMemoryDeliveryTrackingRepository();
    final deliveryEarningsRepository = InMemoryDeliveryEarningsRepository();
    final shiftRepository = InMemoryCourierShiftRepository();
    final scheduleRepository = InMemoryCourierShiftScheduleRepository();
    final shiftEarningsRepository = InMemoryShiftHourlyEarningsRepository();
    final adjustmentRepository = InMemoryCourierEarningsAdjustmentRepository();
    final paymentRepository = InMemoryCourierEarningsPaymentRepository();
    final auditRepository = InMemoryCourierOperationalAuditEntryRepository();

    // --- Manager configures a compensation profile. ---
    final profile = await CreateCourierCompensationProfile(
      clock: clock,
      authorizationPolicy: policy,
      idGenerator: SequentialCourierCompensationProfileIdGenerator(),
      repository: profileRepository,
      auditRepository: auditRepository,
    )(
      courierId: courierId,
      branchId: branchId,
      effectiveFrom: DateTime(2025, 1, 1),
      hourlyRate: Money.fromWhole(30, Currency.tryLira),
      deliveryFeePerPackage: Money.fromWhole(15, Currency.tryLira),
      freeDistanceKm: 2,
      extraDistanceRatePerKm: Money.fromWhole(4, Currency.tryLira),
      performedByStaffId: 'manager-1',
    );
    expect(profile.version, 1);

    // --- A completed delivery earns its package + extra-distance fee. ---
    await deliveryRepository.save(buildTestDelivery(
      status: DeliveryStatus.delivered,
      courierId: courierId,
    ));
    await trackingRepository.append(DeliveryRouteSnapshot(
      id: 'route-1',
      deliveryId: 'delivery-1',
      distanceEstimateMeters: 6000, // 6 km
      computedAt: clock.now(),
    ));
    final deliveryEarnings = await CalculateDeliveryEarnings(
      clock: clock,
      authorizationPolicy: policy,
      idGenerator: SequentialDeliveryEarningsIdGenerator(),
      deliveryRepository: deliveryRepository,
      trackingRepository: trackingRepository,
      compensationProfileRepository: profileRepository,
      earningsRepository: deliveryEarningsRepository,
      auditRepository: auditRepository,
    )(deliveryId: 'delivery-1', performedByStaffId: 'courier-1');
    // 6km - 2km free = 4km extra * 4 TRY = 16 TRY extra; +15 TRY package.
    expect(
        deliveryEarnings.totalEarnings, Money.fromWhole(31, Currency.tryLira));

    // --- A completed shift earns its scheduled hourly window. ---
    await shiftRepository
        .save(buildTestActiveShift(status: CourierShiftStatus.completed));
    await ScheduleCourierShift(
      clock: clock,
      authorizationPolicy: policy,
      idGenerator: SequentialCourierShiftScheduleIdGenerator(),
      shiftRepository: shiftRepository,
      scheduleRepository: scheduleRepository,
      auditRepository: auditRepository,
    )(
      shiftId: 'shift-1',
      scheduledStart: DateTime(2026, 1, 1, 9, 0),
      scheduledEnd: DateTime(2026, 1, 1, 17, 0),
      performedByStaffId: 'manager-1',
    );
    final shiftEarnings = await CalculateShiftHourlyEarnings(
      clock: clock,
      authorizationPolicy: policy,
      idGenerator: SequentialShiftHourlyEarningsIdGenerator(),
      shiftRepository: shiftRepository,
      scheduleRepository: scheduleRepository,
      compensationProfileRepository: profileRepository,
      earningsRepository: shiftEarningsRepository,
      auditRepository: auditRepository,
    )(shiftId: 'shift-1', performedByStaffId: 'manager-1');
    // 8 hours * 30 TRY = 240 TRY.
    expect(
        shiftEarnings.hourlyEarnings, Money.fromWhole(240, Currency.tryLira));

    // --- A manager records a small correction. ---
    final adjustment = await CreateCourierEarningsAdjustment(
      clock: clock,
      authorizationPolicy: policy,
      idGenerator: SequentialCourierEarningsAdjustmentIdGenerator(),
      repository: adjustmentRepository,
      auditRepository: auditRepository,
    )(
      courierId: courierId,
      branchId: branchId,
      relatedDeliveryId: 'delivery-1',
      reason: CourierEarningsAdjustmentReason.customerComplaint,
      amount: -Money.fromWhole(5, Currency.tryLira),
      notes: 'Geç teslimat şikayeti',
      performedByStaffId: 'manager-1',
    );
    expect(adjustment.amount.isNegative, isTrue);

    // --- The dashboard/manager-panel summary reflects everything. ---
    final summary = await BuildCourierEarningsSummary(
      deliveryEarningsRepository: deliveryEarningsRepository,
      shiftEarningsRepository: shiftEarningsRepository,
      adjustmentRepository: adjustmentRepository,
      paymentRepository: paymentRepository,
    )(
      courierId: courierId,
      periodStart: DateTime(2026, 1, 1),
      periodEnd: DateTime(2026, 1, 2),
    );
    // 31 (delivery) + 240 (hourly) - 5 (adjustment) = 266 TRY.
    expect(summary.grossEarnings, Money.fromWhole(266, Currency.tryLira));
    expect(summary.pendingAmount, summary.grossEarnings);
    expect(summary.deliveryLineItems, hasLength(1));

    // --- Manager marks it paid. ---
    final payment = await MarkCourierEarningsPaid(
      clock: clock,
      authorizationPolicy: policy,
      idGenerator: SequentialCourierEarningsPaymentIdGenerator(),
      repository: paymentRepository,
      auditRepository: auditRepository,
    )(
      courierId: courierId,
      branchId: branchId,
      periodStart: DateTime(2026, 1, 1),
      periodEnd: DateTime(2026, 1, 2),
      totalAmount: summary.grossEarnings,
      deliveryEarningsIds: [deliveryEarnings.id],
      shiftEarningsIds: [shiftEarnings.id],
      adjustmentIds: [adjustment.id],
      performedByStaffId: 'manager-1',
    );

    final summaryAfterPayment = await BuildCourierEarningsSummary(
      deliveryEarningsRepository: deliveryEarningsRepository,
      shiftEarningsRepository: shiftEarningsRepository,
      adjustmentRepository: adjustmentRepository,
      paymentRepository: paymentRepository,
    )(
      courierId: courierId,
      periodStart: DateTime(2026, 1, 1),
      periodEnd: DateTime(2026, 1, 2),
    );
    expect(summaryAfterPayment.paidAmount, payment.totalAmount);
    expect(summaryAfterPayment.pendingAmount.isZero, isTrue);

    // --- Paying the same delivery earnings again is structurally
    // rejected — "locked earnings become immutable." ---
    expect(
      () => MarkCourierEarningsPaid(
        clock: clock,
        authorizationPolicy: policy,
        idGenerator: SequentialCourierEarningsPaymentIdGenerator(),
        repository: paymentRepository,
        auditRepository: auditRepository,
      )(
        courierId: courierId,
        branchId: branchId,
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 1, 2),
        totalAmount: Money.fromWhole(1, Currency.tryLira),
        deliveryEarningsIds: [deliveryEarnings.id],
        performedByStaffId: 'manager-1',
      ),
      throwsA(isA<EarningsAlreadyPaidViolation>()),
    );

    // --- A full audit trail exists for every action. ---
    final auditEntries = await auditRepository.findByCourierId(courierId);
    expect(
        auditEntries.map((e) => e.type.name),
        containsAll([
          'compensationProfileCreated',
          'deliveryEarningsCalculated',
          'shiftScheduled',
          'shiftEarningsCalculated',
          'earningsAdjustmentCreated',
          'earningsMarkedPaid',
        ]));
  });
}
