abstract interface class DeliveryProofIdGenerator {
  String nextProofId();
}

class SequentialDeliveryProofIdGenerator implements DeliveryProofIdGenerator {
  SequentialDeliveryProofIdGenerator({this.prefix = 'dproof'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextProofId() => '$prefix-${++_sequence}';
}
