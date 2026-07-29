abstract interface class LocationEmergencyOverrideIdGenerator {
  String nextOverrideId();
}

class SequentialLocationEmergencyOverrideIdGenerator
    implements LocationEmergencyOverrideIdGenerator {
  SequentialLocationEmergencyOverrideIdGenerator({this.prefix = 'locoverride'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextOverrideId() => '$prefix-${++_sequence}';
}
