import '../domain/cash/cash_session.dart';

/// Append-only storage for [CashSession] revisions, keyed by
/// [CashSession.id]. Mirrors `PaymentSessionRepository`'s shape.
abstract interface class CashSessionRepository {
  Future<void> save(CashSession session);

  /// The latest revision for [sessionId], or `null` if unknown.
  Future<CashSession?> findById(String sessionId);

  /// The latest revision of the currently non-closed session for
  /// [drawerId], or `null` if none — what `OpenCashDrawer` checks before
  /// allowing a new session (only one active session per drawer).
  Future<CashSession?> findActiveByDrawerId(String drawerId);

  /// Every session ever opened for [drawerId] (latest revision of each),
  /// oldest first.
  Future<List<CashSession>> findByDrawerId(String drawerId);
}

/// In-memory [CashSessionRepository] — the only implementation this
/// sprint.
class InMemoryCashSessionRepository implements CashSessionRepository {
  final Map<String, List<CashSession>> _historyById = {};

  @override
  Future<void> save(CashSession session) async {
    _historyById.putIfAbsent(session.id, () => []).add(session);
  }

  @override
  Future<CashSession?> findById(String sessionId) async {
    final history = _historyById[sessionId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<CashSession?> findActiveByDrawerId(String drawerId) async {
    for (final history in _historyById.values) {
      if (history.isEmpty) continue;
      final latest = history.last;
      if (latest.drawerId == drawerId && latest.isActive) return latest;
    }
    return null;
  }

  @override
  Future<List<CashSession>> findByDrawerId(String drawerId) async {
    final result = <CashSession>[];
    for (final history in _historyById.values) {
      if (history.isNotEmpty && history.last.drawerId == drawerId) {
        result.add(history.last);
      }
    }
    result.sort((a, b) => a.opening.openedAt.compareTo(b.opening.openedAt));
    return List.unmodifiable(result);
  }
}
