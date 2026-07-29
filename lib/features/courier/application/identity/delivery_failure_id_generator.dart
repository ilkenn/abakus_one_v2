abstract interface class DeliveryFailureIdGenerator {
  String nextFailureId();
}

class SequentialDeliveryFailureIdGenerator
    implements DeliveryFailureIdGenerator {
  SequentialDeliveryFailureIdGenerator({this.prefix = 'dfailure'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextFailureId() => '$prefix-${++_sequence}';
}
