import '../domain/courier_settlement/courier_settlement_adjustment.dart';

/// Append-only storage for [CourierSettlementAdjustment]s — no update
/// method exists at all, mirroring `CashAdjustmentRepository`.
abstract interface class CourierSettlementAdjustmentRepository {
  Future<void> append(CourierSettlementAdjustment adjustment);

  Future<CourierSettlementAdjustment?> findById(String adjustmentId);

  /// Every adjustment recorded for [settlementSessionId], oldest first.
  Future<List<CourierSettlementAdjustment>> findBySettlementSessionId(
      String settlementSessionId);
}

/// In-memory [CourierSettlementAdjustmentRepository] — the only
/// implementation this sprint.
class InMemoryCourierSettlementAdjustmentRepository
    implements CourierSettlementAdjustmentRepository {
  final List<CourierSettlementAdjustment> _adjustments = [];

  @override
  Future<void> append(CourierSettlementAdjustment adjustment) async {
    _adjustments.add(adjustment);
  }

  @override
  Future<CourierSettlementAdjustment?> findById(String adjustmentId) async {
    for (final adjustment in _adjustments) {
      if (adjustment.id == adjustmentId) return adjustment;
    }
    return null;
  }

  @override
  Future<List<CourierSettlementAdjustment>> findBySettlementSessionId(
      String settlementSessionId) async {
    return List.unmodifiable(
      _adjustments.where((a) => a.settlementSessionId == settlementSessionId),
    );
  }
}
