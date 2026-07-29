import '../domain/device/courier_device_session.dart';

/// Append-only storage for [CourierDeviceSession] revisions — mirrors
/// `KitchenDisplaySessionRepository`.
abstract interface class CourierDeviceSessionRepository {
  Future<void> save(CourierDeviceSession session);
  Future<CourierDeviceSession?> findById(String sessionId);
  Future<CourierDeviceSession?> findActiveByDeviceId(String deviceId);
  Future<List<CourierDeviceSession>> findActiveByCourierId(String courierId);
}

class InMemoryCourierDeviceSessionRepository
    implements CourierDeviceSessionRepository {
  final Map<String, List<CourierDeviceSession>> _historyById = {};

  @override
  Future<void> save(CourierDeviceSession session) async {
    _historyById.putIfAbsent(session.id, () => []).add(session);
  }

  @override
  Future<CourierDeviceSession?> findById(String sessionId) async {
    final history = _historyById[sessionId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<CourierDeviceSession?> findActiveByDeviceId(String deviceId) async {
    for (final history in _historyById.values) {
      if (history.isEmpty) continue;
      final latest = history.last;
      if (latest.deviceId == deviceId && latest.isActive) return latest;
    }
    return null;
  }

  @override
  Future<List<CourierDeviceSession>> findActiveByCourierId(
      String courierId) async {
    final result = <CourierDeviceSession>[];
    for (final history in _historyById.values) {
      if (history.isEmpty) continue;
      final latest = history.last;
      if (latest.courierId == courierId && latest.isActive) {
        result.add(latest);
      }
    }
    return List.unmodifiable(result);
  }
}
