import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_compensation_profile_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_shift_schedule_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/create_courier_compensation_profile.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/schedule_courier_shift.dart';
import 'package:abakus_one_v2/features/courier/data/courier_compensation_profile_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_shift_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_shift_schedule_repository.dart';
import 'package:abakus_one_v2/shared/models/currency.dart';
import 'package:abakus_one_v2/shared/models/money.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

void main() {
  group('CreateCourierCompensationProfile', () {
    test('the first profile for a courier is version 1', () async {
      final repository = InMemoryCourierCompensationProfileRepository();
      final useCase = CreateCourierCompensationProfile(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierCompensationProfileIdGenerator(),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final profile = await useCase(
        courierId: 'courier-1',
        branchId: 'branch-1',
        effectiveFrom: DateTime(2026, 1, 1),
        hourlyRate: Money.fromWhole(50, Currency.tryLira),
        performedByStaffId: 'manager-1',
      );
      expect(profile.version, 1);
    });

    test(
        'a second profile for the same courier is version 2 — never '
        'overwrites the first', () async {
      final repository = InMemoryCourierCompensationProfileRepository();
      final useCase = CreateCourierCompensationProfile(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierCompensationProfileIdGenerator(),
        repository: repository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      final first = await useCase(
        courierId: 'courier-1',
        branchId: 'branch-1',
        effectiveFrom: DateTime(2026, 1, 1),
        performedByStaffId: 'manager-1',
      );
      final second = await useCase(
        courierId: 'courier-1',
        branchId: 'branch-1',
        effectiveFrom: DateTime(2026, 3, 1),
        hourlyRate: Money.fromWhole(60, Currency.tryLira),
        performedByStaffId: 'manager-1',
      );
      expect(second.version, 2);

      final all = await repository.findAllByCourierId('courier-1');
      expect(all, hasLength(2));
      expect(all.first.id, first.id);
    });

    test('rejects a negative freeDistanceKm', () async {
      final useCase = CreateCourierCompensationProfile(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierCompensationProfileIdGenerator(),
        repository: InMemoryCourierCompensationProfileRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      expect(
        () => useCase(
          courierId: 'courier-1',
          branchId: 'branch-1',
          effectiveFrom: DateTime(2026, 1, 1),
          freeDistanceKm: -1,
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidCompensationConfigurationViolation>()),
      );
    });

    test('rejects a negative rate', () async {
      final useCase = CreateCourierCompensationProfile(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierCompensationProfileIdGenerator(),
        repository: InMemoryCourierCompensationProfileRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      expect(
        () => useCase(
          courierId: 'courier-1',
          branchId: 'branch-1',
          effectiveFrom: DateTime(2026, 1, 1),
          hourlyRate: const Money(-100, Currency.tryLira),
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidCompensationConfigurationViolation>()),
      );
    });

    test('rejects effectiveUntil at or before effectiveFrom', () async {
      final useCase = CreateCourierCompensationProfile(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierCompensationProfileIdGenerator(),
        repository: InMemoryCourierCompensationProfileRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      expect(
        () => useCase(
          courierId: 'courier-1',
          branchId: 'branch-1',
          effectiveFrom: DateTime(2026, 3, 1),
          effectiveUntil: DateTime(2026, 1, 1),
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidCompensationConfigurationViolation>()),
      );
    });

    test('throws when authorization is denied', () async {
      final useCase = CreateCourierCompensationProfile(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: false)),
        idGenerator: SequentialCourierCompensationProfileIdGenerator(),
        repository: InMemoryCourierCompensationProfileRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      expect(
        () => useCase(
          courierId: 'courier-1',
          branchId: 'branch-1',
          effectiveFrom: DateTime(2026, 1, 1),
          performedByStaffId: 'courier-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });

    test('records a compensationProfileCreated audit entry', () async {
      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      final useCase = CreateCourierCompensationProfile(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierCompensationProfileIdGenerator(),
        repository: InMemoryCourierCompensationProfileRepository(),
        auditRepository: auditRepository,
      );
      await useCase(
        courierId: 'courier-1',
        branchId: 'branch-1',
        effectiveFrom: DateTime(2026, 1, 1),
        performedByStaffId: 'manager-1',
      );
      final entries = await auditRepository.findByCourierId('courier-1');
      expect(entries, hasLength(1));
    });
  });

  group('ScheduleCourierShift', () {
    test('throws for an unknown shift', () async {
      final useCase = ScheduleCourierShift(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierShiftScheduleIdGenerator(),
        shiftRepository: InMemoryCourierShiftRepository(),
        scheduleRepository: InMemoryCourierShiftScheduleRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      expect(
        () => useCase(
          shiftId: 'unknown-shift',
          scheduledStart: DateTime(2026, 1, 1, 10),
          scheduledEnd: DateTime(2026, 1, 1, 18),
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<UnknownCourierEntityViolation>()),
      );
    });

    test('rejects scheduledEnd at or before scheduledStart', () async {
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository.save(buildTestActiveShift());
      final useCase = ScheduleCourierShift(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierShiftScheduleIdGenerator(),
        shiftRepository: shiftRepository,
        scheduleRepository: InMemoryCourierShiftScheduleRepository(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      expect(
        () => useCase(
          shiftId: 'shift-1',
          scheduledStart: DateTime(2026, 1, 1, 18),
          scheduledEnd: DateTime(2026, 1, 1, 10),
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<InvalidCompensationConfigurationViolation>()),
      );
    });

    test('a reschedule appends a new revision — the latest wins', () async {
      final shiftRepository = InMemoryCourierShiftRepository();
      await shiftRepository.save(buildTestActiveShift());
      final scheduleRepository = InMemoryCourierShiftScheduleRepository();
      final useCase = ScheduleCourierShift(
        clock: FakeClock(DateTime(2026, 1, 1)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierShiftScheduleIdGenerator(),
        shiftRepository: shiftRepository,
        scheduleRepository: scheduleRepository,
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );
      await useCase(
        shiftId: 'shift-1',
        scheduledStart: DateTime(2026, 1, 1, 10),
        scheduledEnd: DateTime(2026, 1, 1, 18),
        performedByStaffId: 'manager-1',
      );
      await useCase(
        shiftId: 'shift-1',
        scheduledStart: DateTime(2026, 1, 1, 11),
        scheduledEnd: DateTime(2026, 1, 1, 19),
        performedByStaffId: 'manager-1',
      );
      final latest = await scheduleRepository.findLatestByShiftId('shift-1');
      expect(latest!.scheduledStart, DateTime(2026, 1, 1, 11));
    });
  });
}
