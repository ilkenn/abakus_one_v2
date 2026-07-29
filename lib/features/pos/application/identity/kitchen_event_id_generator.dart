/// Generates a stable id for a new `KitchenEvent`.
abstract interface class KitchenEventIdGenerator {
  String nextEventId();
}

class SequentialKitchenEventIdGenerator implements KitchenEventIdGenerator {
  SequentialKitchenEventIdGenerator({this.prefix = 'kevent'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextEventId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
