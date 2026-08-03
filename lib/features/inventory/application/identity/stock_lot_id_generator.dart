abstract interface class StockLotIdGenerator {
  String nextStockLotId();
}

class SequentialStockLotIdGenerator implements StockLotIdGenerator {
  SequentialStockLotIdGenerator({this.prefix = 'stock-lot'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextStockLotId() => '$prefix-${++_sequence}';
}
