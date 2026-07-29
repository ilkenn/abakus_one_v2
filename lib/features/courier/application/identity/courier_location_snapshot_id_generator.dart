abstract interface class CourierLocationSnapshotIdGenerator {
  String nextSnapshotId();
}

class SequentialCourierLocationSnapshotIdGenerator
    implements CourierLocationSnapshotIdGenerator {
  SequentialCourierLocationSnapshotIdGenerator({this.prefix = 'cloc'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextSnapshotId() => '$prefix-${++_sequence}';
}
