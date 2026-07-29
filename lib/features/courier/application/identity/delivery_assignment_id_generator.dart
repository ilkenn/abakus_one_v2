abstract interface class DeliveryAssignmentIdGenerator {
  String nextAssignmentId();
}

class SequentialDeliveryAssignmentIdGenerator
    implements DeliveryAssignmentIdGenerator {
  SequentialDeliveryAssignmentIdGenerator({this.prefix = 'dassign'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextAssignmentId() => '$prefix-${++_sequence}';
}
