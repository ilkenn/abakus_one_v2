/// Generates a stable id for a new [TableSession].
///
/// See `PaymentSplitIdGenerator`'s doc comment (Sprint 3C) for why this is
/// its own small, single-purpose contract.
abstract interface class TableSessionIdGenerator {
  String nextTableSessionId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialTableSessionIdGenerator implements TableSessionIdGenerator {
  SequentialTableSessionIdGenerator({this.prefix = 'tsession'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextTableSessionId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
