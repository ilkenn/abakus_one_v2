abstract interface class GoodsReceiptIdGenerator {
  String nextGoodsReceiptId();
}

class SequentialGoodsReceiptIdGenerator implements GoodsReceiptIdGenerator {
  SequentialGoodsReceiptIdGenerator({this.prefix = 'goods-receipt'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextGoodsReceiptId() => '$prefix-${++_sequence}';
}
