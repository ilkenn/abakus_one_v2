import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/pos/application/identity/kitchen_display_session_id_generator.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/end_kitchen_display_session.dart';
import 'package:abakus_one_v2/features/pos/application/use_cases/start_kitchen_display_session.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_display_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_display_session.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

void main() {
  group('StartKitchenDisplaySession / EndKitchenDisplaySession', () {
    test('starts a new active session', () async {
      final repository = InMemoryKitchenDisplaySessionRepository();
      final useCase = StartKitchenDisplaySession(
        clock: FakeClock(DateTime(2026, 1, 1, 8)),
        idGenerator: SequentialKitchenDisplaySessionIdGenerator(),
        repository: repository,
      );

      final session = await useCase(deviceId: 'device-1', branchId: 'branch-1');

      expect(session.status, KitchenDisplaySessionStatus.active);
      expect(session.revision, 1);
    });

    test('throws when the device already has an active session', () async {
      final repository = InMemoryKitchenDisplaySessionRepository();
      final useCase = StartKitchenDisplaySession(
        clock: FakeClock(DateTime(2026, 1, 1, 8)),
        idGenerator: SequentialKitchenDisplaySessionIdGenerator(),
        repository: repository,
      );
      await useCase(deviceId: 'device-1', branchId: 'branch-1');

      expect(
        () => useCase(deviceId: 'device-1', branchId: 'branch-1'),
        throwsA(isA<KitchenDisplaySessionAlreadyActiveViolation>()),
      );
    });

    test('ending a session allows a new one to start', () async {
      final repository = InMemoryKitchenDisplaySessionRepository();
      final start = StartKitchenDisplaySession(
        clock: FakeClock(DateTime(2026, 1, 1, 8)),
        idGenerator: SequentialKitchenDisplaySessionIdGenerator(),
        repository: repository,
      );
      final end = EndKitchenDisplaySession(
        clock: FakeClock(DateTime(2026, 1, 1, 20)),
        repository: repository,
      );

      await start(deviceId: 'device-1', branchId: 'branch-1');
      final ended = await end(deviceId: 'device-1');
      expect(ended.status, KitchenDisplaySessionStatus.ended);

      final restarted = await start(deviceId: 'device-1', branchId: 'branch-1');
      expect(restarted.status, KitchenDisplaySessionStatus.active);
    });
  });
}
