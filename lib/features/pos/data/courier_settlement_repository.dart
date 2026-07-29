import '../domain/courier_settlement/courier_settlement.dart';

/// Append-only storage for [CourierSettlement]s — a rejected settlement
/// is never deleted or edited. No update method exists at all, mirroring
/// `CashReconciliationRepository`.
abstract interface class CourierSettlementRepository {
  Future<void> append(CourierSettlement settlement);

  Future<CourierSettlement?> findById(String settlementId);

  /// Every settlement decision ever recorded for [settlementSessionId],
  /// oldest first.
  Future<List<CourierSettlement>> findBySettlementSessionId(
      String settlementSessionId);

  /// The most recent settlement decision for [settlementSessionId], or
  /// `null` if none yet.
  Future<CourierSettlement?> findLatestBySettlementSessionId(
      String settlementSessionId);
}

/// In-memory [CourierSettlementRepository] — the only implementation this
/// sprint.
class InMemoryCourierSettlementRepository
    implements CourierSettlementRepository {
  final List<CourierSettlement> _settlements = [];

  @override
  Future<void> append(CourierSettlement settlement) async {
    _settlements.add(settlement);
  }

  @override
  Future<CourierSettlement?> findById(String settlementId) async {
    for (final settlement in _settlements) {
      if (settlement.id == settlementId) return settlement;
    }
    return null;
  }

  @override
  Future<List<CourierSettlement>> findBySettlementSessionId(
      String settlementSessionId) async {
    return List.unmodifiable(
      _settlements.where((s) => s.settlementSessionId == settlementSessionId),
    );
  }

  @override
  Future<CourierSettlement?> findLatestBySettlementSessionId(
      String settlementSessionId) async {
    final matches = _settlements
        .where((s) => s.settlementSessionId == settlementSessionId)
        .toList();
    if (matches.isEmpty) return null;
    return matches.last;
  }
}
