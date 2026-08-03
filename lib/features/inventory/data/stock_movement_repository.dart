import '../domain/stock_movement.dart';

/// Append-only — no update or delete method exists, matching "stock
/// cannot be edited by overwriting history."
abstract interface class StockMovementRepository {
  Future<void> append(StockMovement movement);
  Future<StockMovement?> findByIdempotencyKey(String idempotencyKey);
  Future<List<StockMovement>> findByItemAndLocation(
      String inventoryItemId, String locationId);
  Future<List<StockMovement>> findByBranchId(String branchId);
}

class InMemoryStockMovementRepository implements StockMovementRepository {
  final List<StockMovement> _movements = [];

  @override
  Future<void> append(StockMovement movement) async {
    _movements.add(movement);
  }

  @override
  Future<StockMovement?> findByIdempotencyKey(String idempotencyKey) async {
    for (final movement in _movements) {
      if (movement.idempotencyKey == idempotencyKey) return movement;
    }
    return null;
  }

  @override
  Future<List<StockMovement>> findByItemAndLocation(
      String inventoryItemId, String locationId) async {
    return List.unmodifiable(
      _movements.where(
        (m) =>
            m.inventoryItemId == inventoryItemId && m.locationId == locationId,
      ),
    );
  }

  @override
  Future<List<StockMovement>> findByBranchId(String branchId) async {
    return List.unmodifiable(_movements.where((m) => m.branchId == branchId));
  }
}
