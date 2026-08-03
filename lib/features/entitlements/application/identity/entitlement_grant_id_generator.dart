abstract interface class EntitlementGrantIdGenerator {
  String nextEntitlementGrantId();
}

class SequentialEntitlementGrantIdGenerator
    implements EntitlementGrantIdGenerator {
  SequentialEntitlementGrantIdGenerator({this.prefix = 'entitlement'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextEntitlementGrantId() => '$prefix-${++_sequence}';
}
