abstract interface class SupplierPriceIdGenerator {
  String nextSupplierPriceId();
}

class SequentialSupplierPriceIdGenerator implements SupplierPriceIdGenerator {
  SequentialSupplierPriceIdGenerator({this.prefix = 'supplier-price'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextSupplierPriceId() => '$prefix-${++_sequence}';
}
