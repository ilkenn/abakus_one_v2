abstract interface class StockConsumptionRecordIdGenerator {
  String nextStockConsumptionRecordId();
}

class SequentialStockConsumptionRecordIdGenerator
    implements StockConsumptionRecordIdGenerator {
  SequentialStockConsumptionRecordIdGenerator({
    this.prefix = 'stock-consumption-record',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextStockConsumptionRecordId() => '$prefix-${++_sequence}';
}
