import '../domain/courier_settlement/courier_settlement_session.dart';

/// Append-only storage for [CourierSettlementSession] revisions, keyed by
/// [CourierSettlementSession.id]. Mirrors `CashSessionRepository`'s shape
/// exactly.
abstract interface class CourierSettlementSessionRepository {
  Future<void> save(CourierSettlementSession session);

  /// The latest revision for [sessionId], or `null` if unknown.
  Future<CourierSettlementSession?> findById(String sessionId);

  /// The latest revision of the currently non-closed session for
  /// [courierId], or `null` if none — what `OpenCourierSettlementSession`
  /// checks before allowing a new session (only one active session per
  /// courier).
  Future<CourierSettlementSession?> findActiveByCourierId(String courierId);

  /// Every session ever opened for [courierId] (latest revision of each),
  /// oldest first.
  Future<List<CourierSettlementSession>> findByCourierId(String courierId);
}

/// In-memory [CourierSettlementSessionRepository] — the only
/// implementation this sprint.
class InMemoryCourierSettlementSessionRepository
    implements CourierSettlementSessionRepository {
  final Map<String, List<CourierSettlementSession>> _historyById = {};

  @override
  Future<void> save(CourierSettlementSession session) async {
    _historyById.putIfAbsent(session.id, () => []).add(session);
  }

  @override
  Future<CourierSettlementSession?> findById(String sessionId) async {
    final history = _historyById[sessionId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<CourierSettlementSession?> findActiveByCourierId(
      String courierId) async {
    for (final history in _historyById.values) {
      if (history.isEmpty) continue;
      final latest = history.last;
      if (latest.courierId == courierId && latest.isActive) return latest;
    }
    return null;
  }

  @override
  Future<List<CourierSettlementSession>> findByCourierId(
      String courierId) async {
    final result = <CourierSettlementSession>[];
    for (final history in _historyById.values) {
      if (history.isNotEmpty && history.last.courierId == courierId) {
        result.add(history.last);
      }
    }
    result.sort((a, b) => a.openedAt.compareTo(b.openedAt));
    return List.unmodifiable(result);
  }
}
