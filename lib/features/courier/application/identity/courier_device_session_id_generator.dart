abstract interface class CourierDeviceSessionIdGenerator {
  String nextSessionId();
}

class SequentialCourierDeviceSessionIdGenerator
    implements CourierDeviceSessionIdGenerator {
  SequentialCourierDeviceSessionIdGenerator({this.prefix = 'cdsession'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextSessionId() => '$prefix-${++_sequence}';
}
