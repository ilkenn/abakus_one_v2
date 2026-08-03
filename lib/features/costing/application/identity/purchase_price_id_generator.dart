abstract interface class PurchasePriceIdGenerator {
  String nextPurchasePriceId();
}

class SequentialPurchasePriceIdGenerator implements PurchasePriceIdGenerator {
  SequentialPurchasePriceIdGenerator({this.prefix = 'purchase-price'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextPurchasePriceId() => '$prefix-${++_sequence}';
}
