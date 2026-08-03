abstract interface class PurchaseOrderIdGenerator {
  String nextPurchaseOrderId();
}

class SequentialPurchaseOrderIdGenerator implements PurchaseOrderIdGenerator {
  SequentialPurchaseOrderIdGenerator({this.prefix = 'purchase-order'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextPurchaseOrderId() => '$prefix-${++_sequence}';
}
