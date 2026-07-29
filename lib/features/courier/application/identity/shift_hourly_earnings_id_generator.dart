abstract interface class ShiftHourlyEarningsIdGenerator {
  String nextEarningsId();
}

class SequentialShiftHourlyEarningsIdGenerator
    implements ShiftHourlyEarningsIdGenerator {
  SequentialShiftHourlyEarningsIdGenerator({this.prefix = 'shiftearnings'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextEarningsId() => '$prefix-${++_sequence}';
}
