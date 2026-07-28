/// Generates a stable id for a new [Check].
///
/// See `PaymentSplitIdGenerator`'s doc comment (Sprint 3C) for why this is
/// its own small, single-purpose contract.
abstract interface class CheckIdGenerator {
  String nextCheckId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialCheckIdGenerator implements CheckIdGenerator {
  SequentialCheckIdGenerator({this.prefix = 'check'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextCheckId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
