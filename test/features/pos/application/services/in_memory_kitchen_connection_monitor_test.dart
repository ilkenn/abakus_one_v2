import 'package:abakus_one_v2/features/pos/application/services/in_memory_kitchen_connection_monitor.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_display_device_repository.dart';
import 'package:abakus_one_v2/features/pos/data/kitchen_display_session_repository.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_display_device.dart';
import 'package:abakus_one_v2/features/pos/domain/kds/kitchen_display_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('InMemoryKitchenConnectionMonitor', () {
    late InMemoryKitchenDisplaySessionRepository sessionRepository;
    late InMemoryKitchenDisplayDeviceRepository deviceRepository;
    late InMemoryKitchenConnectionMonitor monitor;

    setUp(() async {
      sessionRepository = InMemoryKitchenDisplaySessionRepository();
      deviceRepository = InMemoryKitchenDisplayDeviceRepository();
      monitor = InMemoryKitchenConnectionMonitor(
        sessionRepository: sessionRepository,
        deviceRepository: deviceRepository,
      );
      await deviceRepository.save(KitchenDisplayDevice(
        id: 'device-1',
        branchId: 'branch-1',
        name: 'Ekran 1',
        registeredAt: DateTime(2026, 1, 1),
      ));
      await sessionRepository.save(KitchenDisplaySession(
        id: 'session-1',
        deviceId: 'device-1',
        branchId: 'branch-1',
        status: KitchenDisplaySessionStatus.active,
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

    test('findStaleDevices returns only devices past the threshold', () async {
      await deviceRepository.save(KitchenDisplayDevice(
        id: 'device-2',
        branchId: 'branch-1',
        name: 'Ekran 2',
        registeredAt: DateTime(2026, 1, 1),
      ));
      await sessionRepository.save(KitchenDisplaySession(
        id: 'session-2',
        deviceId: 'device-2',
        branchId: 'branch-1',
        status: KitchenDisplaySessionStatus.active,
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
