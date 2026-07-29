/// Generates a stable id for a new `KitchenDisplaySession`.
abstract interface class KitchenDisplaySessionIdGenerator {
  String nextSessionId();
}

class SequentialKitchenDisplaySessionIdGenerator
    implements KitchenDisplaySessionIdGenerator {
  SequentialKitchenDisplaySessionIdGenerator({this.prefix = 'kdsession'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextSessionId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
