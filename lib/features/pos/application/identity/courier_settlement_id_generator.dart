/// Generates a stable id for a new `CourierSettlement`.
abstract interface class CourierSettlementIdGenerator {
  String nextSettlementId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialCourierSettlementIdGenerator
    implements CourierSettlementIdGenerator {
  SequentialCourierSettlementIdGenerator({this.prefix = 'csettlement'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextSettlementId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
