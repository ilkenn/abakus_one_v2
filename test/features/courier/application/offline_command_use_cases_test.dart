import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/courier/application/identity/pending_courier_command_id_generator.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/retry_pending_courier_commands.dart';
import 'package:abakus_one_v2/features/courier/application/use_cases/submit_offline_courier_command.dart';
import 'package:abakus_one_v2/features/courier/data/pending_courier_command_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/events/pending_courier_command.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

void main() {
  group('SubmitOfflineCourierCommand', () {
    test(
        'is idempotent by idempotencyKey — a retried submission returns '
        'the same queued command, not a duplicate', () async {
      final repository = InMemoryPendingCourierCommandRepository();
      final useCase = SubmitOfflineCourierCommand(
        clock: FakeClock(DateTime(2026, 1, 1)),
        idGenerator: SequentialPendingCourierCommandIdGenerator(),
        repository: repository,
      );

      final first = await useCase(
        deviceId: 'device-1',
        courierId: 'courier-1',
        commandType: 'RespondToDeliveryAssignment',
        idempotencyKey: 'k1',
      );
      final second = await useCase(
        deviceId: 'device-1',
        courierId: 'courier-1',
        commandType: 'RespondToDeliveryAssignment',
        idempotencyKey: 'k1',
      );

      expect(second.id, first.id);
      expect(await repository.findQueuedByDeviceId('device-1'), hasLength(1));
    });
  });

  group('RetryPendingCourierCommands', () {
    Future<PendingCourierCommandRepository> queueOne() async {
      final repository = InMemoryPendingCourierCommandRepository();
      await repository.save(PendingCourierCommand(
        id: 'cmd-1',
        deviceId: 'device-1',
        courierId: 'courier-1',
        commandType: 'RespondToDeliveryAssignment',
        idempotencyKey: 'k1',
        createdAt: DateTime(2026, 1, 1),
      ));
      return repository;
    }

    test('a successful apply marks the command applied', () async {
      final repository = await queueOne();
      final useCase = RetryPendingCourierCommands(
        clock: FakeClock(DateTime(2026, 1, 1, 1)),
        repository: repository,
      );
      final results = await useCase(
        deviceId: 'device-1',
        applyCommand: (command) async {},
      );
      expect(results.single.status, PendingCourierCommandStatus.applied);
    });

    test(
        'a StaleCourierRevisionViolation becomes a conflict, not a '
        'silent wrong write', () async {
      final repository = await queueOne();
      final useCase = RetryPendingCourierCommands(
        clock: FakeClock(DateTime(2026, 1, 1, 1)),
        repository: repository,
      );
      final results = await useCase(
        deviceId: 'device-1',
        applyCommand: (command) async {
          throw const StaleCourierRevisionViolation(
            entityId: 'delivery-1',
            expectedRevision: 1,
            actualRevision: 2,
          );
        },
      );
      expect(results.single.status, PendingCourierCommandStatus.conflict);
    });

    test('any other BusinessRuleViolation becomes failed', () async {
      final repository = await queueOne();
      final useCase = RetryPendingCourierCommands(
        clock: FakeClock(DateTime(2026, 1, 1, 1)),
        repository: repository,
      );
      final results = await useCase(
        deviceId: 'device-1',
        applyCommand: (command) async {
          throw const UnknownCourierEntityViolation(
              entityName: 'Delivery', id: 'delivery-1');
        },
      );
      expect(results.single.status, PendingCourierCommandStatus.failed);
    });

    test('only queued commands for the given device are retried', () async {
      final repository = await queueOne();
      await repository.save(PendingCourierCommand(
        id: 'cmd-2',
        deviceId: 'device-2',
        courierId: 'courier-2',
        commandType: 'RespondToDeliveryAssignment',
        idempotencyKey: 'k2',
        createdAt: DateTime(2026, 1, 1),
      ));
      final useCase = RetryPendingCourierCommands(
        clock: FakeClock(DateTime(2026, 1, 1, 1)),
        repository: repository,
      );
      final results = await useCase(
        deviceId: 'device-1',
        applyCommand: (command) async {},
      );
      expect(results, hasLength(1));
      expect(results.single.id, 'cmd-1');
    });
  });
}
