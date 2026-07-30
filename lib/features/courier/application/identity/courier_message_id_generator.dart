abstract interface class CourierMessageIdGenerator {
  String nextMessageId();
}

class SequentialCourierMessageIdGenerator implements CourierMessageIdGenerator {
  SequentialCourierMessageIdGenerator({this.prefix = 'cmsg'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextMessageId() => '$prefix-${++_sequence}';
}
