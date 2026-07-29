abstract interface class PendingCourierCommandIdGenerator {
  String nextCommandId();
}

class SequentialPendingCourierCommandIdGenerator
    implements PendingCourierCommandIdGenerator {
  SequentialPendingCourierCommandIdGenerator({this.prefix = 'ccommand'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextCommandId() => '$prefix-${++_sequence}';
}
