/// Generates a stable id for a new `KitchenPrintAttempt`.
abstract interface class KitchenPrintAttemptIdGenerator {
  String nextAttemptId();
}

class SequentialKitchenPrintAttemptIdGenerator
    implements KitchenPrintAttemptIdGenerator {
  SequentialKitchenPrintAttemptIdGenerator({this.prefix = 'kprint'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextAttemptId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
