import '../../../../core/errors/business_rule_violation.dart';
import '../../data/kitchen_display_device_repository.dart';
import '../../data/kitchen_display_session_repository.dart';
import '../../domain/kds/kitchen_connection_monitor.dart';
import '../../domain/kds/kitchen_display_device.dart';
import '../../domain/kds/kitchen_display_session.dart';

/// The only [KitchenConnectionMonitor] implementation this phase — backed
/// by [KitchenDisplaySessionRepository]. Staleness is always computed
/// from [KitchenDisplaySession.lastHeartbeatAt] against a caller-supplied
/// threshold/`now`, never a stored flag.
class InMemoryKitchenConnectionMonitor implements KitchenConnectionMonitor {
  InMemoryKitchenConnectionMonitor({
    required KitchenDisplaySessionRepository sessionRepository,
    required KitchenDisplayDeviceRepository deviceRepository,
  })  : _sessionRepository = sessionRepository,
        _deviceRepository = deviceRepository;

  final KitchenDisplaySessionRepository _sessionRepository;
  final KitchenDisplayDeviceRepository _deviceRepository;

  @override
  Future<void> recordHeartbeat({
    required String deviceId,
    required DateTime at,
  }) async {
    final session = await _sessionRepository.findActiveByDeviceId(deviceId);
    if (session == null) {
      throw UnknownKdsEntityViolation(
        entityName: 'KitchenDisplaySession',
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
  Future<List<KitchenDisplayDevice>> findStaleDevices({
    required String branchId,
    required Duration staleAfter,
    required DateTime now,
  }) async {
    final activeSessions =
        await _sessionRepository.findActiveByBranchId(branchId);
    final staleDeviceIds = {
      for (final session in activeSessions)
        if (now.difference(session.lastHeartbeatAt) > staleAfter)
          session.deviceId,
    };
    final devices = await _deviceRepository.findByBranchId(branchId);
    return List.unmodifiable(
      devices.where((d) => staleDeviceIds.contains(d.id)),
    );
  }
}
