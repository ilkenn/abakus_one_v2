abstract interface class AdminDeviceRegistrationIdGenerator {
  String nextAdminDeviceRegistrationId();
}

class SequentialAdminDeviceRegistrationIdGenerator
    implements AdminDeviceRegistrationIdGenerator {
  SequentialAdminDeviceRegistrationIdGenerator({this.prefix = 'device'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextAdminDeviceRegistrationId() => '$prefix-${++_sequence}';
}
