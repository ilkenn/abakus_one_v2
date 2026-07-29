import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_earnings_adjustment_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_earnings_payment_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/create_courier_earnings_adjustment.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/mark_courier_earnings_paid.dart';
import 'package:abakus_one_v2/features/courier/data/courier_earnings_adjustment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_earnings_payment_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/compensation/courier_earnings_adjustment_reason.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';

void main() {
  group('CreateCourierEarningsAdjustment', () {
    test('creates an append-only adjustment with a predefined reason',
        () async {
      final repository = InMemoryCourierEarningsAdjustmentRepository();
      final useCase = CreateCourierEarningsAdjustment(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierEarningsAdjustmentIdGenerator(),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final adjustment = await useCase(
        courierId: 'courier-1',
        branchId: 'branch-1',
        reason: CourierEarningsAdjustmentReason.gpsProblem,
        amount: Money.fromWhole(15, Currency.tryLira),
        notes: 'GPS sinyali kesildi',
        performedByStaffId: 'manager-1',
      );
      expect(adjustment.reason, CourierEarningsAdjustmentReason.gpsProblem);
      expect(adjustment.amount, Money.fromWhole(15, Currency.tryLira));

      final byPeriod = await repository.findByCourierIdAndPeriod(
        courierId: 'courier-1',
        periodStart: DateTime(2025, 12, 1),
        periodEnd: DateTime(2026, 2, 1),
      );
      expect(byPeriod, hasLength(1));
    });

    test('a negative amount (deduction) is accepted', () async {
      final useCase = CreateCourierEarningsAdjustment(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierEarningsAdjustmentIdGenerator(),
        repository: InMemoryCourierEarningsAdjustmentRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final adjustment = await useCase(
        courierId: 'courier-1',
        branchId: 'branch-1',
        reason: CourierEarningsAdjustmentReason.manualCorrection,
        amount: -Money.fromWhole(10, Currency.tryLira),
        performedByStaffId: 'manager-1',
      );
      expect(adjustment.amount.isNegative, isTrue);
    });

    test('throws when authorization is denied', () async {
      final useCase = CreateCourierEarningsAdjustment(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: false)),
        idGenerator: SequentialCourierEarningsAdjustmentIdGenerator(),
        repository: InMemoryCourierEarningsAdjustmentRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      expect(
        () => useCase(
          courierId: 'courier-1',
          branchId: 'branch-1',
          reason: CourierEarningsAdjustmentReason.manualCorrection,
          amount: Money.fromWhole(10, Currency.tryLira),
          performedByStaffId: 'courier-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('MarkCourierEarningsPaid', () {
    test('rejects paying the same earnings id twice across two payments',
        () async {
      final repository = InMemoryCourierEarningsPaymentRepository();
      final useCase = MarkCourierEarningsPaid(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierEarningsPaymentIdGenerator(),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      await useCase(
        courierId: 'courier-1',
        branchId: 'branch-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 2, 1),
        totalAmount: Money.fromWhole(50, Currency.tryLira),
        deliveryEarningsIds: const ['de-1'],
        performedByStaffId: 'manager-1',
      );
      expect(
        () => useCase(
          courierId: 'courier-1',
          branchId: 'branch-1',
          periodStart: DateTime(2026, 2, 1),
          periodEnd: DateTime(2026, 3, 1),
          totalAmount: Money.fromWhole(20, Currency.tryLira),
          deliveryEarningsIds: const ['de-1'],
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<EarningsAlreadyPaidViolation>()),
      );
    });

    test('succeeds for a fresh set of ids and records the payment', () async {
      final repository = InMemoryCourierEarningsPaymentRepository();
      final useCase = MarkCourierEarningsPaid(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierEarningsPaymentIdGenerator(),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final payment = await useCase(
        courierId: 'courier-1',
        branchId: 'branch-1',
        periodStart: DateTime(2026, 1, 1),
        periodEnd: DateTime(2026, 2, 1),
        totalAmount: Money.fromWhole(50, Currency.tryLira),
        deliveryEarningsIds: const ['de-1', 'de-2'],
        shiftEarningsIds: const ['se-1'],
        performedByStaffId: 'manager-1',
      );
      expect(payment.deliveryEarningsIds, ['de-1', 'de-2']);

      final referenced = await repository.findByReferencedId('de-1');
      expect(referenced, hasLength(1));
    });

    test('throws when authorization is denied', () async {
      final useCase = MarkCourierEarningsPaid(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: false)),
        idGenerator: SequentialCourierEarningsPaymentIdGenerator(),
        repository: InMemoryCourierEarningsPaymentRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      expect(
        () => useCase(
          courierId: 'courier-1',
          branchId: 'branch-1',
          periodStart: DateTime(2026, 1, 1),
          periodEnd: DateTime(2026, 2, 1),
          totalAmount: Money.fromWhole(50, Currency.tryLira),
          performedByStaffId: 'courier-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
