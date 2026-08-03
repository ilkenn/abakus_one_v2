import '../domain/stock_consumption_record.dart';

abstract interface class StockConsumptionRecordRepository {
  Future<void> save(StockConsumptionRecord record);
  Future<StockConsumptionRecord?> findByIdempotencyKey(String idempotencyKey);
  Future<StockConsumptionRecord?> findByOrderLineId(String orderLineId);
}

class InMemoryStockConsumptionRecordRepository
    implements StockConsumptionRecordRepository {
  final Map<String, StockConsumptionRecord> _byIdempotencyKey = {};

  @override
  Future<void> save(StockConsumptionRecord record) async {
    _byIdempotencyKey[record.idempotencyKey] = record;
  }

  @override
  Future<StockConsumptionRecord?> findByIdempotencyKey(
      String idempotencyKey) async {
    return _byIdempotencyKey[idempotencyKey];
  }

  @override
  Future<StockConsumptionRecord?> findByOrderLineId(String orderLineId) async {
    for (final record in _byIdempotencyKey.values) {
      if (record.orderLineId == orderLineId) return record;
    }
    return null;
  }
}
