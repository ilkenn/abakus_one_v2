abstract interface class DeliveryIdGenerator {
  String nextDeliveryId();
}

class SequentialDeliveryIdGenerator implements DeliveryIdGenerator {
  SequentialDeliveryIdGenerator({this.prefix = 'delivery'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextDeliveryId() => '$prefix-${++_sequence}';
}
