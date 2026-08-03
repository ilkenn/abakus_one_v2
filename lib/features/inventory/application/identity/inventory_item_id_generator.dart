abstract interface class InventoryItemIdGenerator {
  String nextInventoryItemId();
}

class SequentialInventoryItemIdGenerator implements InventoryItemIdGenerator {
  SequentialInventoryItemIdGenerator({this.prefix = 'inventory-item'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextInventoryItemId() => '$prefix-${++_sequence}';
}
