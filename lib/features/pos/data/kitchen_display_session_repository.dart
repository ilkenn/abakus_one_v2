import '../domain/kds/kitchen_display_session.dart';

/// Append-only storage for [KitchenDisplaySession] revisions, keyed by
/// [KitchenDisplaySession.id]. Mirrors `CashSessionRepository`'s shape.
abstract interface class KitchenDisplaySessionRepository {
  Future<void> save(KitchenDisplaySession session);

  Future<KitchenDisplaySession?> findById(String sessionId);

  /// The active session for [deviceId], or `null` if none — what
  /// `StartKitchenDisplaySession` checks before starting a new one, and
  /// what heartbeats/staleness checks read.
  Future<KitchenDisplaySession?> findActiveByDeviceId(String deviceId);

  /// The active session of every device in [branchId] — what
  /// `findStaleDevices` scans.
  Future<List<KitchenDisplaySession>> findActiveByBranchId(String branchId);
}

/// In-memory [KitchenDisplaySessionRepository] — the only implementation
/// this phase.
class InMemoryKitchenDisplaySessionRepository
    implements KitchenDisplaySessionRepository {
  final Map<String, List<KitchenDisplaySession>> _historyById = {};

  @override
  Future<void> save(KitchenDisplaySession session) async {
    _historyById.putIfAbsent(session.id, () => []).add(session);
  }

  @override
  Future<KitchenDisplaySession?> findById(String sessionId) async {
    final history = _historyById[sessionId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<KitchenDisplaySession?> findActiveByDeviceId(String deviceId) async {
    for (final history in _historyById.values) {
      if (history.isEmpty) continue;
      final latest = history.last;
      if (latest.deviceId == deviceId && latest.isActive) return latest;
    }
    return null;
  }

  @override
  Future<List<KitchenDisplaySession>> findActiveByBranchId(
      String branchId) async {
    final result = <KitchenDisplaySession>[];
    for (final history in _historyById.values) {
      if (history.isEmpty) continue;
      final latest = history.last;
      if (latest.branchId == branchId && latest.isActive) {
        result.add(latest);
      }
    }
    return List.unmodifiable(result);
  }
}
