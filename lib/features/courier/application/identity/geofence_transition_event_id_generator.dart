abstract interface class GeofenceTransitionEventIdGenerator {
  String nextTransitionId();
}

class SequentialGeofenceTransitionEventIdGenerator
    implements GeofenceTransitionEventIdGenerator {
  SequentialGeofenceTransitionEventIdGenerator({this.prefix = 'geotrans'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextTransitionId() => '$prefix-${++_sequence}';
}
