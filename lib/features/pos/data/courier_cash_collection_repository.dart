import '../domain/courier_settlement/courier_cash_collection.dart';

/// Append-only storage for [CourierCashCollection]s — no update or delete
/// method exists (collections are immutable and never removed, mirroring
/// `CashMovementRepository`).
abstract interface class CourierCashCollectionRepository {
  Future<void> append(CourierCashCollection collection);

  Future<CourierCashCollection?> findById(String collectionId);

  /// Every collection recorded for [settlementSessionId], oldest first.
  Future<List<CourierCashCollection>> findBySettlementSessionId(
      String settlementSessionId);
}

/// In-memory [CourierCashCollectionRepository] — the only implementation
/// this sprint.
class InMemoryCourierCashCollectionRepository
    implements CourierCashCollectionRepository {
  final List<CourierCashCollection> _collections = [];

  @override
  Future<void> append(CourierCashCollection collection) async {
    _collections.add(collection);
  }

  @override
  Future<CourierCashCollection?> findById(String collectionId) async {
    for (final collection in _collections) {
      if (collection.id == collectionId) return collection;
    }
    return null;
  }

  @override
  Future<List<CourierCashCollection>> findBySettlementSessionId(
      String settlementSessionId) async {
    return List.unmodifiable(
      _collections.where((c) => c.settlementSessionId == settlementSessionId),
    );
  }
}
