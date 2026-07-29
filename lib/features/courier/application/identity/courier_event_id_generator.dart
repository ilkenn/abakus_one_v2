abstract interface class CourierEventIdGenerator {
  String nextEventId();
}

class SequentialCourierEventIdGenerator implements CourierEventIdGenerator {
  SequentialCourierEventIdGenerator({this.prefix = 'cevent'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextEventId() => '$prefix-${++_sequence}';
}
