import '../domain/cash/cash_adjustment.dart';

/// Append-only storage for [CashAdjustment]s — no update or delete method
/// exists; a further correction is always another [CashAdjustment], never
/// an edit to a previous one.
abstract interface class CashAdjustmentRepository {
  Future<void> append(CashAdjustment adjustment);

  /// Every adjustment ever recorded for [sessionId], oldest first.
  Future<List<CashAdjustment>> findBySessionId(String sessionId);
}

/// In-memory [CashAdjustmentRepository] — the only implementation this
/// sprint.
class InMemoryCashAdjustmentRepository implements CashAdjustmentRepository {
  final List<CashAdjustment> _adjustments = [];

  @override
  Future<void> append(CashAdjustment adjustment) async {
    _adjustments.add(adjustment);
  }

  @override
  Future<List<CashAdjustment>> findBySessionId(String sessionId) async {
    return List.unmodifiable(
      _adjustments.where((a) => a.sessionId == sessionId),
    );
  }
}
