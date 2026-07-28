import '../domain/models/check.dart';

/// Append-only storage for [Check] revisions, keyed by [Check.id].
abstract interface class CheckRepository {
  Future<void> save(Check check);

  /// The latest revision for [checkId], or `null` if unknown.
  Future<Check?> findById(String checkId);

  /// The latest revision of every check ever opened under
  /// [tableSessionId].
  Future<List<Check>> findByTableSessionId(String tableSessionId);
}

/// In-memory [CheckRepository] — the only implementation this sprint.
class InMemoryCheckRepository implements CheckRepository {
  final Map<String, List<Check>> _historyById = {};

  @override
  Future<void> save(Check check) async {
    _historyById.putIfAbsent(check.id, () => []).add(check);
  }

  @override
  Future<Check?> findById(String checkId) async {
    final history = _historyById[checkId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<List<Check>> findByTableSessionId(String tableSessionId) async {
    final result = <Check>[];
    for (final history in _historyById.values) {
      if (history.isNotEmpty && history.last.tableSessionId == tableSessionId) {
        result.add(history.last);
      }
    }
    return List.unmodifiable(result);
  }
}
