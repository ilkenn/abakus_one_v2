abstract interface class StockAdjustmentIdGenerator {
  String nextStockAdjustmentId();
}

class SequentialStockAdjustmentIdGenerator
    implements StockAdjustmentIdGenerator {
  SequentialStockAdjustmentIdGenerator({this.prefix = 'stock-adjustment'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextStockAdjustmentId() => '$prefix-${++_sequence}';
}
