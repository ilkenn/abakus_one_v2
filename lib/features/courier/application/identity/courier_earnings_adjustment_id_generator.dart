abstract interface class CourierEarningsAdjustmentIdGenerator {
  String nextAdjustmentId();
}

class SequentialCourierEarningsAdjustmentIdGenerator
    implements CourierEarningsAdjustmentIdGenerator {
  SequentialCourierEarningsAdjustmentIdGenerator({this.prefix = 'earningsadj'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextAdjustmentId() => '$prefix-${++_sequence}';
}
