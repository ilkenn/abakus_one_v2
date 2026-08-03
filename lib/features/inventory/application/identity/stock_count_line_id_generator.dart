abstract interface class StockCountLineIdGenerator {
  String nextStockCountLineId();
}

class SequentialStockCountLineIdGenerator implements StockCountLineIdGenerator {
  SequentialStockCountLineIdGenerator({this.prefix = 'stock-count-line'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextStockCountLineId() => '$prefix-${++_sequence}';
}
