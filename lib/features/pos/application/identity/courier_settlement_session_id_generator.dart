/// Generates a stable id for a new `CourierSettlementSession`.
abstract interface class CourierSettlementSessionIdGenerator {
  String nextSettlementSessionId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialCourierSettlementSessionIdGenerator
    implements CourierSettlementSessionIdGenerator {
  SequentialCourierSettlementSessionIdGenerator({this.prefix = 'csession'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextSettlementSessionId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
