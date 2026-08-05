/// Mirrors every other `Sequential*IdGenerator` in this codebase.
abstract interface class DeviceTokenIdGenerator {
  String nextTokenId();
}

class SequentialDeviceTokenIdGenerator implements DeviceTokenIdGenerator {
  SequentialDeviceTokenIdGenerator({this.prefix = 'device-token'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextTokenId() => '$prefix-${++_sequence}';
}
