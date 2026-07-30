import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_location_audit_action_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/identity/courier_location_snapshot_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/record_courier_location_snapshot.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/reset_courier_location_history.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/start_courier_location_tracking.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/stop_courier_location_tracking.dart';
import 'package:abakus_one_v2/features/courier/data/courier_location_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/audit/courier_audit_event_type.dart';
import 'package:abakus_one_v2/features/courier/domain/location/background_location_session.dart';
import 'package:abakus_one_v2/features/pos/domain/authorization/authorization_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../../pos/test_support/fake_pos_authorization_policy.dart';
import '../test_support/courier_test_fixtures.dart';

class _FakeSession implements BackgroundLocationSession {
  bool started = false;
  bool stopped = false;

  @override
  Future<void> start({
    required String courierId,
    required String deviceId,
  }) async {
    started = true;
  }

  @override
  Future<void> stop({
    required String courierId,
    required String deviceId,
  }) async {
    stopped = true;
  }

  @override
  bool get isActive => started && !stopped;
}

void main() {
  group('StartCourierLocationTracking', () {
    test('denied authorization never starts the session or audits', () async {
      final session = _FakeSession();
      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      final useCase = StartCourierLocationTracking(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: false)),
        session: session,
        idGenerator: SequentialCourierLocationAuditActionIdGenerator(),
        auditRepository: auditRepository,
      );

      await expectLater(
        () => useCase(
          branchId: 'branch-1',
          courierId: 'courier-1',
          deviceId: 'device-1',
          performedByStaffId: 'courier-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
      expect(session.started, isFalse);
      expect(await auditRepository.findByCourierId('courier-1'), isEmpty);
    });

    test('granted authorization starts the session and audits it', () async {
      final session = _FakeSession();
      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      final useCase = StartCourierLocationTracking(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        session: session,
        idGenerator: SequentialCourierLocationAuditActionIdGenerator(),
        auditRepository: auditRepository,
      );

      await useCase(
        branchId: 'branch-1',
        courierId: 'courier-1',
        deviceId: 'device-1',
        performedByStaffId: 'courier-1',
      );

      expect(session.started, isTrue);
      final entries = await auditRepository.findByCourierId('courier-1');
      expect(
          entries.single.type, CourierAuditEventType.locationTrackingStarted);
    });
  });

  group('StopCourierLocationTracking', () {
    test('granted authorization stops the session and audits it', () async {
      final session = _FakeSession()..started = true;
      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      final useCase = StopCourierLocationTracking(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        session: session,
        idGenerator: SequentialCourierLocationAuditActionIdGenerator(),
        auditRepository: auditRepository,
      );

      await useCase(
        branchId: 'branch-1',
        courierId: 'courier-1',
        deviceId: 'device-1',
        performedByStaffId: 'courier-1',
      );

      expect(session.stopped, isTrue);
      final entries = await auditRepository.findByCourierId('courier-1');
      expect(
          entries.single.type, CourierAuditEventType.locationTrackingStopped);
    });
  });

  group('ResetCourierLocationHistory', () {
    test('an empty reason is rejected before authorization is even checked',
        () async {
      final policy =
          FakePosAuthorizationPolicy(const AuthorizationResult(granted: true));
      final useCase = ResetCourierLocationHistory(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: policy,
        idGenerator: SequentialCourierLocationAuditActionIdGenerator(),
        auditRepository: InMemoryCourierOperationalAuditEntryRepository(),
      );

      await expectLater(
        () => useCase(
          branchId: 'branch-1',
          courierId: 'courier-1',
          reason: '   ',
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<ManualOverrideReasonRequiredViolation>()),
      );
      expect(policy.callCount, 0);
    });

    test(
        'a granted, reasoned reset never touches CourierLocationRepository '
        '— only produces an audit entry', () async {
      final locationRepository = InMemoryCourierLocationRepository();
      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      final useCase = ResetCourierLocationHistory(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: true)),
        idGenerator: SequentialCourierLocationAuditActionIdGenerator(),
        auditRepository: auditRepository,
      );

      await useCase(
        branchId: 'branch-1',
        courierId: 'courier-1',
        reason: 'Cihaz değişikliği sonrası temiz başlangıç',
        performedByStaffId: 'manager-1',
      );

      final entries = await auditRepository.findByCourierId('courier-1');
      expect(entries.single.type, CourierAuditEventType.locationHistoryReset);
      expect(
          await locationRepository.findLatestByCourierId('courier-1'), isNull);
    });

    test('denied authorization throws and never audits', () async {
      final auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      final useCase = ResetCourierLocationHistory(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        authorizationPolicy: FakePosAuthorizationPolicy(
            const AuthorizationResult(granted: false)),
        idGenerator: SequentialCourierLocationAuditActionIdGenerator(),
        auditRepository: auditRepository,
      );

      await expectLater(
        () => useCase(
          branchId: 'branch-1',
          courierId: 'courier-1',
          reason: 'reason',
          performedByStaffId: 'manager-1',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
      expect(await auditRepository.findByCourierId('courier-1'), isEmpty);
    });
  });

  group('RecordCourierLocationSnapshot self-only publishing', () {
    test(
        'a mismatched authenticatedCourierId is rejected before anything '
        'is recorded', () async {
      final repository = InMemoryCourierLocationRepository();
      final useCase = RecordCourierLocationSnapshot(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialCourierLocationSnapshotIdGenerator(),
        repository: repository,
        recordCourierEvent: buildTestRecordCourierEvent(),
      );

      await expectLater(
        () => useCase(
          courierId: 'courier-1',
          deviceId: 'device-1',
          branchId: 'branch-1',
          latitude: 41.0,
          longitude: 29.0,
          accuracyMeters: 10,
          capturedAt: DateTime(2026, 1, 1, 12),
          authenticatedCourierId: 'courier-2',
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
      expect(await repository.findLatestByCourierId('courier-1'), isNull);
    });

    test('a matching authenticatedCourierId records normally', () async {
      final repository = InMemoryCourierLocationRepository();
      final useCase = RecordCourierLocationSnapshot(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialCourierLocationSnapshotIdGenerator(),
        repository: repository,
        recordCourierEvent: buildTestRecordCourierEvent(),
      );

      final snapshot = await useCase(
        courierId: 'courier-1',
        deviceId: 'device-1',
        branchId: 'branch-1',
        latitude: 41.0,
        longitude: 29.0,
        accuracyMeters: 10,
        capturedAt: DateTime(2026, 1, 1, 12),
        authenticatedCourierId: 'courier-1',
      );
      expect(snapshot.courierId, 'courier-1');
    });

    test(
        'omitting authenticatedCourierId (null) never triggers the check '
        '— every existing caller keeps working unchanged', () async {
      final repository = InMemoryCourierLocationRepository();
      final useCase = RecordCourierLocationSnapshot(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialCourierLocationSnapshotIdGenerator(),
        repository: repository,
        recordCourierEvent: buildTestRecordCourierEvent(),
      );

      final snapshot = await useCase(
        courierId: 'courier-1',
        deviceId: 'device-1',
        branchId: 'branch-1',
        latitude: 41.0,
        longitude: 29.0,
        accuracyMeters: 10,
        capturedAt: DateTime(2026, 1, 1, 12),
      );
      expect(snapshot.courierId, 'courier-1');
    });
  });
}
