abstract interface class DeliveryRouteSnapshotIdGenerator {
  String nextSnapshotId();
}

class SequentialDeliveryRouteSnapshotIdGenerator
    implements DeliveryRouteSnapshotIdGenerator {
  SequentialDeliveryRouteSnapshotIdGenerator({this.prefix = 'droute'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextSnapshotId() => '$prefix-${++_sequence}';
}
