/// Generates a stable id for a new `KitchenDisplayDevice`.
abstract interface class KitchenDisplayDeviceIdGenerator {
  String nextDeviceId();
}

class SequentialKitchenDisplayDeviceIdGenerator
    implements KitchenDisplayDeviceIdGenerator {
  SequentialKitchenDisplayDeviceIdGenerator({this.prefix = 'kdevice'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextDeviceId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
