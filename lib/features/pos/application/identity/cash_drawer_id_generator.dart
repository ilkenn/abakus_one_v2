/// Generates a stable id for a new [CashDrawer].
abstract interface class CashDrawerIdGenerator {
  String nextDrawerId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialCashDrawerIdGenerator implements CashDrawerIdGenerator {
  SequentialCashDrawerIdGenerator({this.prefix = 'drawer'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextDrawerId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
