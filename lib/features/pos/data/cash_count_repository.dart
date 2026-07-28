import '../domain/cash/cash_count.dart';

/// Append-only storage for [CashCount]s — **never overwritten**; a
/// recount is always a new record. No update method exists at all.
abstract interface class CashCountRepository {
  Future<void> append(CashCount count);

  Future<CashCount?> findById(String countId);

  /// Every count ever submitted for [sessionId], oldest first.
  Future<List<CashCount>> findBySessionId(String sessionId);

  /// The most recently submitted count for [sessionId], or `null` if none
  /// yet.
  Future<CashCount?> findLatestBySessionId(String sessionId);
}

/// In-memory [CashCountRepository] — the only implementation this
/// sprint.
class InMemoryCashCountRepository implements CashCountRepository {
  final List<CashCount> _counts = [];

  @override
  Future<void> append(CashCount count) async {
    _counts.add(count);
  }

  @override
  Future<CashCount?> findById(String countId) async {
    for (final count in _counts) {
      if (count.id == countId) return count;
    }
    return null;
  }

  @override
  Future<List<CashCount>> findBySessionId(String sessionId) async {
    return List.unmodifiable(
      _counts.where((count) => count.sessionId == sessionId),
    );
  }

  @override
  Future<CashCount?> findLatestBySessionId(String sessionId) async {
    final matches =
        _counts.where((count) => count.sessionId == sessionId).toList();
    if (matches.isEmpty) return null;
    return matches.last;
  }
}
