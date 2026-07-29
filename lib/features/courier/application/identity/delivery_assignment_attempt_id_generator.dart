abstract interface class DeliveryAssignmentAttemptIdGenerator {
  String nextAttemptId();
}

class SequentialDeliveryAssignmentAttemptIdGenerator
    implements DeliveryAssignmentAttemptIdGenerator {
  SequentialDeliveryAssignmentAttemptIdGenerator({this.prefix = 'dattempt'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextAttemptId() => '$prefix-${++_sequence}';
}
