/// Generates a stable id for a new `CourierSettlementAdjustment`.
abstract interface class CourierSettlementAdjustmentIdGenerator {
  String nextAdjustmentId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialCourierSettlementAdjustmentIdGenerator
    implements CourierSettlementAdjustmentIdGenerator {
  SequentialCourierSettlementAdjustmentIdGenerator(
      {this.prefix = 'cadjustment'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextAdjustmentId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
