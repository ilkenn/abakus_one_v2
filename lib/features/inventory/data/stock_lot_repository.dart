import '../domain/stock_lot.dart';

abstract interface class StockLotRepository {
  Future<void> save(StockLot lot);
  Future<StockLot?> findById(String id);
  Future<List<StockLot>> findByItemAndLocation(
      String inventoryItemId, String locationId);

  /// Every lot with a non-null `expiresAt`, across every item — used by
  /// expiry-warning screens.
  Future<List<StockLot>> findExpiringByLocationId(String locationId);
}

class InMemoryStockLotRepository implements StockLotRepository {
  final Map<String, StockLot> _byId = {};

  @override
  Future<void> save(StockLot lot) async => _byId[lot.id] = lot;

  @override
  Future<StockLot?> findById(String id) async => _byId[id];

  @override
  Future<List<StockLot>> findByItemAndLocation(
      String inventoryItemId, String locationId) async {
    return List.unmodifiable(
      _byId.values.where(
        (l) =>
            l.inventoryItemId == inventoryItemId && l.locationId == locationId,
      ),
    );
  }

  @override
  Future<List<StockLot>> findExpiringByLocationId(String locationId) async {
    return List.unmodifiable(
      _byId.values.where(
        (l) => l.locationId == locationId && l.expiresAt != null,
      ),
    );
  }
}
