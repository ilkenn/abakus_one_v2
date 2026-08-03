abstract interface class PurchaseOrderLineIdGenerator {
  String nextPurchaseOrderLineId();
}

class SequentialPurchaseOrderLineIdGenerator
    implements PurchaseOrderLineIdGenerator {
  SequentialPurchaseOrderLineIdGenerator({
    this.prefix = 'purchase-order-line',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextPurchaseOrderLineId() => '$prefix-${++_sequence}';
}
