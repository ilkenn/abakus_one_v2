/// Generates a stable id for a new [CashAdjustment].
abstract interface class CashAdjustmentIdGenerator {
  String nextAdjustmentId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialCashAdjustmentIdGenerator implements CashAdjustmentIdGenerator {
  SequentialCashAdjustmentIdGenerator({this.prefix = 'adjustment'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextAdjustmentId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
