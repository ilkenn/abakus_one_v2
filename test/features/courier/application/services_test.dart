import 'package:abakus_one_v2/features/courier/application/services/in_memory_courier_connection_monitor.dart';
import 'package:abakus_one_v2/features/courier/application/services/in_memory_courier_synchronization_service.dart';
import 'package:abakus_one_v2/features/courier/data/courier_device_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_device_session_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_event_cursor_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_event_repository.dart';
import 'package:abakus_one_v2/features/courier/data/courier_repository.dart';
import 'package:abakus_one_v2/features/courier/domain/device/courier_device.dart';
import 'package:abakus_one_v2/features/courier/domain/device/courier_device_session.dart';
import 'package:abakus_one_v2/features/courier/domain/events/courier_event.dart';
import 'package:abakus_one_v2/features/courier/domain/events/courier_event_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';
import '../test_support/courier_test_fixtures.dart';

CourierEvent _event(String id) {
  return CourierEvent(
    id: id,
    branchId: 'branch-1',
    type: CourierEventType.deliveryCreated,
    idempotencyKey: id,
    sequence: 0,
    occurredAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('InMemoryCourierSynchronizationService', () {
    test('a fresh device replays every event from the start', () async {
      final eventRepository = InMemoryCourierEventRepository();
      await eventRepository.append(_event('e1'));
      await eventRepository.append(_event('e2'));
      final service = InMemoryCourierSynchronizationService(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        eventRepository: eventRepository,
        cursorRepository: InMemoryCourierEventCursorRepository(),
      );

      final result =
          await service.synchronize(deviceId: 'device-1', branchId: 'branch-1');

      expect(result.events.map((e) => e.id), ['e1', 'e2']);
      expect(result.state.isSynchronized, isTrue);
    });

    test('reconnect after a gap only replays events since the last cursor',
        () async {
      final eventRepository = InMemoryCourierEventRepository();
      await eventRepository.append(_event('e1'));
      final cursorRepository = InMemoryCourierEventCursorRepository();
      final service = InMemoryCourierSynchronizationService(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        eventRepository: eventRepository,
        cursorRepository: cursorRepository,
      );
      await service.synchronize(deviceId: 'device-1', branchId: 'branch-1');

      await eventRepository.append(_event('e2'));

      final result =
          await service.synchronize(deviceId: 'device-1', branchId: 'branch-1');
      expect(result.events.map((e) => e.id), ['e2']);
    });

    test('two devices independently track their own cursors', () async {
      final eventRepository = InMemoryCourierEventRepository();
      await eventRepository.append(_event('e1'));
      final service = InMemoryCourierSynchronizationService(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        eventRepository: eventRepository,
        cursorRepository: InMemoryCourierEventCursorRepository(),
      );

      final deviceA =
          await service.synchronize(deviceId: 'device-A', branchId: 'branch-1');
      await eventRepository.append(_event('e2'));
      final deviceB =
          await service.synchronize(deviceId: 'device-B', branchId: 'branch-1');

      expect(deviceA.events.map((e) => e.id), ['e1']);
      expect(deviceB.events.map((e) => e.id), ['e1', 'e2']);
    });

    test('currentState reports pending count without consuming the batch',
        () async {
      final eventRepository = InMemoryCourierEventRepository();
      await eventRepository.append(_event('e1'));
      final service = InMemoryCourierSynchronizationService(
        clock: FakeClock(DateTime(2026, 1, 1, 12)),
        eventRepository: eventRepository,
        cursorRepository: InMemoryCourierEventCursorRepository(),
      );

      final state = await service.currentState(
          deviceId: 'device-1', branchId: 'branch-1');
      expect(state.isSynchronized, isFalse);
      expect(state.pendingEventCount, 1);

      final syncResult =
          await service.synchronize(deviceId: 'device-1', branchId: 'branch-1');
      expect(syncResult.events, hasLength(1));
    });
  });

  group('InMemoryCourierConnectionMonitor', () {
    late InMemoryCourierDeviceSessionRepository sessionRepository;
    late InMemoryCourierDeviceRepository deviceRepository;
    late InMemoryCourierRepository courierRepository;
    late InMemoryCourierConnectionMonitor monitor;

    setUp(() async {
      sessionRepository = InMemoryCourierDeviceSessionRepository();
      deviceRepository = InMemoryCourierDeviceRepository();
      courierRepository = InMemoryCourierRepository();
      monitor = InMemoryCourierConnectionMonitor(
        sessionRepository: sessionRepository,
        deviceRepository: deviceRepository,
        courierRepository: courierRepository,
      );
      await courierRepository.save(buildTestCourier());
      await deviceRepository.save(CourierDevice(
        id: 'device-1',
        courierId: 'courier-1',
        registeredAt: DateTime(2026, 1, 1),
      ));
      await sessionRepository.save(CourierDeviceSession(
        id: 'session-1',
        deviceId: 'device-1',
        courierId: 'courier-1',
        status: CourierDeviceSessionStatus.active,
        startedAt: DateTime(2026, 1, 1, 8),
        lastHeartbeatAt: DateTime(2026, 1, 1, 8),
        revision: 1,
      ));
    });

    test('is not stale immediately after a heartbeat', () async {
      await monitor.recordHeartbeat(
          deviceId: 'device-1', at: DateTime(2026, 1, 1, 9));

      final stale = await monitor.isStale(
        deviceId: 'device-1',
        staleAfter: const Duration(minutes: 5),
        now: DateTime(2026, 1, 1, 9, 1),
      );
      expect(stale, isFalse);
    });

    test('becomes stale once past the threshold since the last heartbeat',
        () async {
      final stale = await monitor.isStale(
        deviceId: 'device-1',
        staleAfter: const Duration(minutes: 5),
        now: DateTime(2026, 1, 1, 8, 10),
      );
      expect(stale, isTrue);
    });

    test(
        'findStaleDevices resolves branch scope via CourierRepository, '
        'since CourierDevice has no branchId of its own', () async {
      await courierRepository
          .save(buildTestCourier(id: 'courier-2', displayName: 'Ayşe'));
      await deviceRepository.save(CourierDevice(
        id: 'device-2',
        courierId: 'courier-2',
        registeredAt: DateTime(2026, 1, 1),
      ));
      await sessionRepository.save(CourierDeviceSession(
        id: 'session-2',
        deviceId: 'device-2',
        courierId: 'courier-2',
        status: CourierDeviceSessionStatus.active,
        startedAt: DateTime(2026, 1, 1, 8),
        lastHeartbeatAt: DateTime(2026, 1, 1, 8, 59),
        revision: 1,
      ));

      final stale = await monitor.findStaleDevices(
        branchId: 'branch-1',
        staleAfter: const Duration(minutes: 5),
        now: DateTime(2026, 1, 1, 9),
      );

      expect(stale.map((d) => d.id), ['device-1']);
    });
  });
}
