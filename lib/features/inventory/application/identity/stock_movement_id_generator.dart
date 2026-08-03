abstract interface class StockMovementIdGenerator {
  String nextStockMovementId();
}

class SequentialStockMovementIdGenerator implements StockMovementIdGenerator {
  SequentialStockMovementIdGenerator({this.prefix = 'stock-movement'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextStockMovementId() => '$prefix-${++_sequence}';
}
