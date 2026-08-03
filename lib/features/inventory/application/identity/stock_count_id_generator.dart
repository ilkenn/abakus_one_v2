abstract interface class StockCountIdGenerator {
  String nextStockCountId();
}

class SequentialStockCountIdGenerator implements StockCountIdGenerator {
  SequentialStockCountIdGenerator({this.prefix = 'stock-count'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextStockCountId() => '$prefix-${++_sequence}';
}
