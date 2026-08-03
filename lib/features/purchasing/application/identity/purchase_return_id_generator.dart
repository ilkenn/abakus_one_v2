abstract interface class PurchaseReturnIdGenerator {
  String nextPurchaseReturnId();
}

class SequentialPurchaseReturnIdGenerator implements PurchaseReturnIdGenerator {
  SequentialPurchaseReturnIdGenerator({this.prefix = 'purchase-return'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextPurchaseReturnId() => '$prefix-${++_sequence}';
}
