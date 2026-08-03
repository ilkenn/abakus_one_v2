abstract interface class GoodsReceiptLineIdGenerator {
  String nextGoodsReceiptLineId();
}

class SequentialGoodsReceiptLineIdGenerator
    implements GoodsReceiptLineIdGenerator {
  SequentialGoodsReceiptLineIdGenerator({
    this.prefix = 'goods-receipt-line',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextGoodsReceiptLineId() => '$prefix-${++_sequence}';
}
