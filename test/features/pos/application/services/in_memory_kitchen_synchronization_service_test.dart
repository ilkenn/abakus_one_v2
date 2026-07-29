import 'package:abakus_one_v2/features/pos/application/services/in_memory_kitchen_synchronization_service.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_event_cursor_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_event_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_event.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_event_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_support/fake_clock.dart';

KitchenEvent _event(String id) {
  return KitchenEvent(
    id: id,
    branchId: 'branch-1',
    type: KitchenEventType.workItemQueued,
    idempotencyKey: id,
    sequence: 0,
    occurredAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('InMemoryKitchenSynchronizationService', () {
    test('a fresh device replays every event from the start', () async {
      final eventRepository = InMemoryKitchenEventRepository();
      await eventRepository.append(_event('e1'));
      await eventRepository.append(_event('e2'));
      final service = InMemoryKitchenSynchronizationService(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        eventRepository: eventRepository,
        cursorRepository: InMemoryKitchenEventCursorRepository(),
      );

      final result =
          await service.synchronize(deviceId: 'device-1', branchId: 'branch-1');

      expect(result.events.map((e) => e.id), ['e1', 'e2']);
      expect(result.state.isSynchronized, isTrue);
    });

    test(
        'resyncing again before any new event returns an empty batch — '
        'idempotent replay', () async {
      final eventRepository = InMemoryKitchenEventRepository();
      await eventRepository.append(_event('e1'));
      final cursorRepository = InMemoryKitchenEventCursorRepository();
      final service = InMemoryKitchenSynchronizationService(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        eventRepository: eventRepository,
        cursorRepository: cursorRepository,
      );

      await service.synchronize(deviceId: 'device-1', branchId: 'branch-1');
      final second =
          await service.synchronize(deviceId: 'device-1', branchId: 'branch-1');

      expect(second.events, isEmpty);
    });

    test('reconnect after a gap only replays events since the last cursor',
        () async {
      final eventRepository = InMemoryKitchenEventRepository();
      await eventRepository.append(_event('e1'));
      final cursorRepository = InMemoryKitchenEventCursorRepository();
      final service = InMemoryKitchenSynchronizationService(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        eventRepository: eventRepository,
        cursorRepository: cursorRepository,
      );
      await service.synchronize(deviceId: 'device-1', branchId: 'branch-1');

      // A new event fires while the device was disconnected.
      await eventRepository.append(_event('e2'));

      final result =
          await service.synchronize(deviceId: 'device-1', branchId: 'branch-1');
      expect(result.events.map((e) => e.id), ['e2']);
    });

    test('two devices independently track their own cursors', () async {
      final eventRepository = InMemoryKitchenEventRepository();
      await eventRepository.append(_event('e1'));
      final cursorRepository = InMemoryKitchenEventCursorRepository();
      final service = InMemoryKitchenSynchronizationService(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        eventRepository: eventRepository,
        cursorRepository: cursorRepository,
      );

      final deviceAFirstSync =
          await service.synchronize(deviceId: 'device-A', branchId: 'branch-1');
      await eventRepository.append(_event('e2'));
      final deviceBFirstSync =
          await service.synchronize(deviceId: 'device-B', branchId: 'branch-1');

      expect(deviceAFirstSync.events.map((e) => e.id), ['e1']);
      expect(deviceBFirstSync.events.map((e) => e.id), ['e1', 'e2']);
    });

    test('currentState reports pending count without consuming the batch',
        () async {
      final eventRepository = InMemoryKitchenEventRepository();
      await eventRepository.append(_event('e1'));
      final service = InMemoryKitchenSynchronizationService(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        eventRepository: eventRepository,
        cursorRepository: InMemoryKitchenEventCursorRepository(),
      );

      final state = await service.currentState(
          deviceId: 'device-1', branchId: 'branch-1');
      expect(state.isSynchronized, isFalse);
      expect(state.pendingEventCount, 1);

      // currentState must not have advanced the cursor.
      final syncResult =
          await service.synchronize(deviceId: 'device-1', branchId: 'branch-1');
      expect(syncResult.events, hasLength(1));
    });
  });
}
