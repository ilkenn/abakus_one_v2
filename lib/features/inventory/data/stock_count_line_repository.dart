import 'package:cloud_firestore/cloud_firestore.dart' as fs;

import '../domain/inventory_unit.dart';
import '../domain/quantity.dart';
import '../domain/stock_count_line.dart';

/// Append-only — "counts never delete movement history," and a
/// submitted count's lines are likewise never edited; a recount
/// creates a new `StockCount` with its own new lines.
abstract interface class StockCountLineRepository {
  Future<void> save(StockCountLine line);
  Future<List<StockCountLine>> findByCountId(String countId);
}

class InMemoryStockCountLineRepository implements StockCountLineRepository {
  final List<StockCountLine> _lines = [];

  @override
  Future<void> save(StockCountLine line) async {
    _lines.add(line);
  }

  @override
  Future<List<StockCountLine>> findByCountId(String countId) async {
    return List.unmodifiable(_lines.where((l) => l.countId == countId));
  }
}

/// AP-5 Sprint 6 — direct Firestore reads of the real `stockCountLines`
/// collection `submitStockCount.ts` (Sprint 3) writes, mirroring
/// `FirestoreStockCountRepository`'s exact shape. `save` is a deliberate
/// no-op (Cloud Function only — `firestore.rules` denies every client
/// write on this collection, same as `stockCounts`).
class FirestoreStockCountLineRepository implements StockCountLineRepository {
  FirestoreStockCountLineRepository({fs.FirebaseFirestore? firestore})
      : _providedFirestore = firestore;

  final fs.FirebaseFirestore? _providedFirestore;
  fs.FirebaseFirestore get _firestore =>
      _providedFirestore ?? fs.FirebaseFirestore.instance;

  @override
  Future<void> save(StockCountLine line) async {}

  @override
  Future<List<StockCountLine>> findByCountId(String countId) async {
    final snap = await _firestore
        .collection('stockCountLines')
        .where('countId', isEqualTo: countId)
        .get();
    return List.unmodifiable(snap.docs
        .map((doc) => _mapLine(doc.id, doc.data()))
        .whereType<StockCountLine>());
  }

  /// `null` when the persisted `unitCode` isn't one of
  /// [InventoryUnit.builtIn] — a tenant-defined custom unit has no
  /// server-side conversion this client can resolve either; the line is
  /// omitted from the result rather than guessed at, mirroring
  /// `acceptOrderLine.ts`'s own identical "unrecognized unit -> omit,
  /// never fabricate" rule for the cost snapshot (AP-5 Sprint 5).
  StockCountLine? _mapLine(String id, Map<String, dynamic> data) {
    final unitCode = data['unitCode'] as String;
    final unit = InventoryUnit.byCode(unitCode);
    if (unit == null) return null;
    return StockCountLine(
      id: id,
      countId: data['countId'] as String,
      inventoryItemId: data['inventoryItemId'] as String,
      expectedQuantity:
          Quantity(data['expectedQuantitySmallestUnits'] as int, unit),
      countedQuantity:
          Quantity(data['countedQuantitySmallestUnits'] as int, unit),
    );
  }
}
