/// Generates a stable id for a new `KitchenWorkItem`.
abstract interface class KitchenWorkItemIdGenerator {
  String nextWorkItemId();
}

class SequentialKitchenWorkItemIdGenerator
    implements KitchenWorkItemIdGenerator {
  SequentialKitchenWorkItemIdGenerator({this.prefix = 'kwork'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextWorkItemId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
