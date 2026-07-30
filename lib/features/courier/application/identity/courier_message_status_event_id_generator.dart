abstract interface class CourierMessageStatusEventIdGenerator {
  String nextStatusEventId();
}

class SequentialCourierMessageStatusEventIdGenerator
    implements CourierMessageStatusEventIdGenerator {
  SequentialCourierMessageStatusEventIdGenerator({this.prefix = 'cmsgstatus'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextStatusEventId() => '$prefix-${++_sequence}';
}
