abstract interface class CourierEarningsPaymentIdGenerator {
  String nextPaymentId();
}

class SequentialCourierEarningsPaymentIdGenerator
    implements CourierEarningsPaymentIdGenerator {
  SequentialCourierEarningsPaymentIdGenerator({this.prefix = 'earningspay'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextPaymentId() => '$prefix-${++_sequence}';
}
