abstract interface class CourierFraudSignalIdGenerator {
  String nextSignalId();
}

class SequentialCourierFraudSignalIdGenerator
    implements CourierFraudSignalIdGenerator {
  SequentialCourierFraudSignalIdGenerator({this.prefix = 'fraudsig'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextSignalId() => '$prefix-${++_sequence}';
}
