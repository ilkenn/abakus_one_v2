abstract interface class StockLocationIdGenerator {
  String nextStockLocationId();
}

class SequentialStockLocationIdGenerator implements StockLocationIdGenerator {
  SequentialStockLocationIdGenerator({this.prefix = 'stock-location'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextStockLocationId() => '$prefix-${++_sequence}';
}
