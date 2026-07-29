abstract interface class CourierShiftScheduleIdGenerator {
  String nextScheduleId();
}

class SequentialCourierShiftScheduleIdGenerator
    implements CourierShiftScheduleIdGenerator {
  SequentialCourierShiftScheduleIdGenerator({this.prefix = 'cshiftsched'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextScheduleId() => '$prefix-${++_sequence}';
}
