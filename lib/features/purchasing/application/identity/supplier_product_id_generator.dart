abstract interface class SupplierProductIdGenerator {
  String nextSupplierProductId();
}

class SequentialSupplierProductIdGenerator
    implements SupplierProductIdGenerator {
  SequentialSupplierProductIdGenerator({this.prefix = 'supplier-product'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextSupplierProductId() => '$prefix-${++_sequence}';
}
