/// Generates a stable id for a new [CashCount].
abstract interface class CashCountIdGenerator {
  String nextCountId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialCashCountIdGenerator implements CashCountIdGenerator {
  SequentialCashCountIdGenerator({this.prefix = 'count'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextCountId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
