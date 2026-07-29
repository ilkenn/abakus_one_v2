import '../../../../core/errors/business_rule_violation.dart';
import '../../data/courier_device_repository.dart';
import '../../data/courier_device_session_repository.dart';
import '../../data/courier_repository.dart';
import '../../domain/device/courier_device.dart';
import '../../domain/events/courier_connection_monitor.dart';

/// The only [CourierConnectionMonitor] implementation this phase — mirrors
/// `InMemoryKitchenConnectionMonitor`'s shape exactly, as a deliberately
/// separate type.
///
/// `CourierDevice`/`CourierDeviceSession` carry no `branchId` of their own
/// (a device belongs to a courier, not directly to a branch) — branch
/// scoping for [findStaleDevices] is resolved by first finding the
/// branch's couriers via [CourierRepository], then their devices.
class InMemoryCourierConnectionMonitor implements CourierConnectionMonitor {
  InMemoryCourierConnectionMonitor({
    required CourierDeviceSessionRepository sessionRepository,
    required CourierDeviceRepository deviceRepository,
    required CourierRepository courierRepository,
  })  : _sessionRepository = sessionRepository,
        _deviceRepository = deviceRepository,
        _courierRepository = courierRepository;

  final CourierDeviceSessionRepository _sessionRepository;
  final CourierDeviceRepository _deviceRepository;
  final CourierRepository _courierRepository;

  @override
  Future<void> recordHeartbeat({
    required String deviceId,
    required DateTime at,
  }) async {
    final session = await _sessionRepository.findActiveByDeviceId(deviceId);
    if (session == null) {
      throw UnknownCourierEntityViolation(
        entityName: 'CourierDeviceSession',
        id: deviceId,
      );
    }
    await _sessionRepository.save(session.copyWith(
      lastHeartbeatAt: at,
      revision: session.revision + 1,
    ));
  }

  @override
  Future<bool> isStale({
    required String deviceId,
    required Duration staleAfter,
    required DateTime now,
  }) async {
    final session = await _sessionRepository.findActiveByDeviceId(deviceId);
    if (session == null) return true;
    return now.difference(session.lastHeartbeatAt) > staleAfter;
  }

  @override
  Future<List<CourierDevice>> findStaleDevices({
    required String branchId,
    required Duration staleAfter,
    required DateTime now,
  }) async {
    final couriers = await _courierRepository.findByBranchId(branchId);
    final staleDevices = <CourierDevice>[];
    for (final courier in couriers) {
      final devices = await _deviceRepository.findByCourierId(courier.id);
      for (final device in devices) {
        final session =
            await _sessionRepository.findActiveByDeviceId(device.id);
        if (session == null ||
            now.difference(session.lastHeartbeatAt) > staleAfter) {
          staleDevices.add(device);
        }
      }
    }
    return List.unmodifiable(staleDevices);
  }
}
