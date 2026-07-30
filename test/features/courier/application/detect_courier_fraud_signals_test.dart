import 'package:abakus_one_v2/features/courier/application/identity/courier_fraud_signal_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/detect_courier_fraud_signals.dart';
import 'package:abakus_one_v2/features/courier/data/courier_fraud_signal_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_operational_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/fraud/courier_fraud_signal_type.dart';
import 'package:abakus_one_v2/features/courier/domain/location/courier_location_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

CourierLocationSnapshot _snapshot({
  double latitude = 41.0,
  double longitude = 29.0,
  double accuracyMeters = 10,
  required DateTime capturedAt,
  bool isMocked = false,
}) {
  return CourierLocationSnapshot(
    id: 'loc-1',
    courierId: 'courier-1',
    deviceId: 'device-1',
    latitude: latitude,
    longitude: longitude,
    accuracyMeters: accuracyMeters,
    isMocked: isMocked,
    capturedAt: capturedAt,
    receivedAt: capturedAt,
  );
}

void main() {
  group('DetectCourierFraudSignals', () {
    late CourierFraudSignalRepository repository;
    late CourierOperationalAuditEntryRepository auditRepository;
    late DetectCourierFraudSignals useCase;

    setUp(() {
      repository = InMemoryCourierFraudSignalRepository();
      auditRepository = InMemoryCourierOperationalAuditEntryRepository();
      useCase = DetectCourierFraudSignals(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        idGenerator: SequentialCourierFraudSignalIdGenerator(),
        repository: repository,
        auditRepository: auditRepository,
      );
    });

    test('no previous snapshot and a genuine reading produces no signals',
        () async {
      final signals = await useCase(
        branchId: 'branch-1',
        current: _snapshot(capturedAt: DateTime(2026, 1, 1, 12)),
      );
      expect(signals, isEmpty);
      expect(await repository.findByCourierId('courier-1'), isEmpty);
    });

    test(
        'an impossible jump between two readings produces an '
        'impossibleSpeed signal, persisted and audited', () async {
      final previous = _snapshot(
        latitude: 41.0,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 0, 0),
      );
      final current = _snapshot(
        latitude: 41.1,
        longitude: 29.0,
        capturedAt: DateTime(2026, 1, 1, 12, 0, 1),
      );

      final signals = await useCase(
        branchId: 'branch-1',
        current: current,
        previous: previous,
      );

      expect(
        signals.map((s) => s.type),
        contains(CourierFraudSignalType.impossibleSpeed),
      );
      final stored = await repository.findByCourierId('courier-1');
      expect(stored, isNotEmpty);
    });

    test(
        'a mocked reading produces a mockLocationDetected signal even '
        'with no previous reading', () async {
      final signals = await useCase(
        branchId: 'branch-1',
        current: _snapshot(
          capturedAt: DateTime(2026, 1, 1, 12),
          isMocked: true,
        ),
      );
      expect(
        signals.map((s) => s.type),
        contains(CourierFraudSignalType.mockLocationDetected),
      );
    });

    test('a plausible pair of readings produces no signals', () async {
      final previous = _snapshot(capturedAt: DateTime(2026, 1, 1, 12, 0, 0));
      final current = _snapshot(
        latitude: 41.00001,
        capturedAt: DateTime(2026, 1, 1, 12, 0, 1),
      );
      final signals = await useCase(
        branchId: 'branch-1',
        current: current,
        previous: previous,
      );
      expect(signals, isEmpty);
    });

    test(
        'never throws, regardless of how implausible the reading is '
        '(no punishment, generation only)', () async {
      final previous = _snapshot(
        latitude: 0,
        longitude: 0,
        capturedAt: DateTime(2026, 1, 1, 12, 0, 0),
      );
      final current = _snapshot(
        latitude: 89,
        longitude: 179,
        capturedAt: DateTime(2026, 1, 1, 12, 0, 1),
        isMocked: true,
      );
      expect(
        () =>
            useCase(branchId: 'branch-1', current: current, previous: previous),
        returnsNormally,
      );
    });
  });
}
