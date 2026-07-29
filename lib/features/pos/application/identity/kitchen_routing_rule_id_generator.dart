/// Generates a stable id for a new `KitchenRoutingRule`.
abstract interface class KitchenRoutingRuleIdGenerator {
  String nextRuleId();
}

class SequentialKitchenRoutingRuleIdGenerator
    implements KitchenRoutingRuleIdGenerator {
  SequentialKitchenRoutingRuleIdGenerator({this.prefix = 'kroute'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextRuleId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
