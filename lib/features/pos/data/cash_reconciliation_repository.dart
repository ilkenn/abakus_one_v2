import '../domain/cash/cash_reconciliation.dart';

/// Append-only storage for [CashReconciliation]s — a rejected
/// reconciliation is never deleted or edited (`docs/business_rules.md`:
/// rejected counts remain in history). No update method exists at all.
abstract interface class CashReconciliationRepository {
  Future<void> append(CashReconciliation reconciliation);

  Future<CashReconciliation?> findById(String reconciliationId);

  /// Every reconciliation ever recorded for [sessionId], oldest first.
  Future<List<CashReconciliation>> findBySessionId(String sessionId);

  /// The most recent reconciliation for [sessionId], or `null` if none
  /// yet.
  Future<CashReconciliation?> findLatestBySessionId(String sessionId);
}

/// In-memory [CashReconciliationRepository] — the only implementation
/// this sprint.
class InMemoryCashReconciliationRepository
    implements CashReconciliationRepository {
  final List<CashReconciliation> _reconciliations = [];

  @override
  Future<void> append(CashReconciliation reconciliation) async {
    _reconciliations.add(reconciliation);
  }

  @override
  Future<CashReconciliation?> findById(String reconciliationId) async {
    for (final reconciliation in _reconciliations) {
      if (reconciliation.id == reconciliationId) return reconciliation;
    }
    return null;
  }

  @override
  Future<List<CashReconciliation>> findBySessionId(String sessionId) async {
    return List.unmodifiable(
      _reconciliations.where((r) => r.sessionId == sessionId),
    );
  }

  @override
  Future<CashReconciliation?> findLatestBySessionId(String sessionId) async {
    final matches =
        _reconciliations.where((r) => r.sessionId == sessionId).toList();
    if (matches.isEmpty) return null;
    return matches.last;
  }
}
