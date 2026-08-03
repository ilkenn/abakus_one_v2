abstract interface class SupplierIdGenerator {
  String nextSupplierId();
}

class SequentialSupplierIdGenerator implements SupplierIdGenerator {
  SequentialSupplierIdGenerator({this.prefix = 'supplier'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextSupplierId() => '$prefix-${++_sequence}';
}
