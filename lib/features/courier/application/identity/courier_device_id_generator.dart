abstract interface class CourierDeviceIdGenerator {
  String nextDeviceId();
}

class SequentialCourierDeviceIdGenerator implements CourierDeviceIdGenerator {
  SequentialCourierDeviceIdGenerator({this.prefix = 'cdevice'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextDeviceId() => '$prefix-${++_sequence}';
}
