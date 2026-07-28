/// Generates a stable id for a new [CashMovement].
abstract interface class CashMovementIdGenerator {
  String nextMovementId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialCashMovementIdGenerator implements CashMovementIdGenerator {
  SequentialCashMovementIdGenerator({this.prefix = 'movement'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextMovementId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
