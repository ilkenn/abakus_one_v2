abstract interface class CourierShiftIdGenerator {
  String nextShiftId();
}

class SequentialCourierShiftIdGenerator implements CourierShiftIdGenerator {
  SequentialCourierShiftIdGenerator({this.prefix = 'cshift'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextShiftId() => '$prefix-${++_sequence}';
}
