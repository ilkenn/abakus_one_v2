abstract interface class MenuProductIdGenerator {
  String nextMenuProductId();
}

class SequentialMenuProductIdGenerator implements MenuProductIdGenerator {
  SequentialMenuProductIdGenerator({this.prefix = 'menu-product'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextMenuProductId() => '$prefix-${++_sequence}';
}
