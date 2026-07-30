abstract interface class CourierDispatchQueueEventIdGenerator {
  String nextEventId();
}

class SequentialCourierDispatchQueueEventIdGenerator
    implements CourierDispatchQueueEventIdGenerator {
  SequentialCourierDispatchQueueEventIdGenerator({this.prefix = 'dispq'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextEventId() => '$prefix-${++_sequence}';
}
