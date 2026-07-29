abstract interface class GeofenceOverrideIdGenerator {
  String nextOverrideId();
}

class SequentialGeofenceOverrideIdGenerator
    implements GeofenceOverrideIdGenerator {
  SequentialGeofenceOverrideIdGenerator({this.prefix = 'geooverride'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextOverrideId() => '$prefix-${++_sequence}';
}
