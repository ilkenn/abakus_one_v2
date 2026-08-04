abstract interface class VirtualRestaurantIdGenerator {
  String nextVirtualRestaurantId();
}

class SequentialVirtualRestaurantIdGenerator
    implements VirtualRestaurantIdGenerator {
  SequentialVirtualRestaurantIdGenerator({this.prefix = 'virtual-restaurant'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextVirtualRestaurantId() => '$prefix-${++_sequence}';
}
