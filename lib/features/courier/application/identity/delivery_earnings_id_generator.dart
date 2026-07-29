abstract interface class DeliveryEarningsIdGenerator {
  String nextEarningsId();
}

class SequentialDeliveryEarningsIdGenerator
    implements DeliveryEarningsIdGenerator {
  SequentialDeliveryEarningsIdGenerator({this.prefix = 'dearnings'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextEarningsId() => '$prefix-${++_sequence}';
}
