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
