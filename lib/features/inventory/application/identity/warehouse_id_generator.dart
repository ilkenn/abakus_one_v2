abstract interface class WarehouseIdGenerator {
  String nextWarehouseId();
}

class SequentialWarehouseIdGenerator implements WarehouseIdGenerator {
  SequentialWarehouseIdGenerator({this.prefix = 'warehouse'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextWarehouseId() => '$prefix-${++_sequence}';
}
