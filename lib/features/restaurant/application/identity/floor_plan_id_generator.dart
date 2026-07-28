/// Generates a stable id for a new [FloorPlan].
///
/// Deliberately its own small, single-purpose contract rather than folded
/// into `OrderIdentityProvider` — same reasoning `PosOrderLineDraftIdGenerator`/
/// `PaymentSplitIdGenerator` already established (`docs/decisions.md`
/// ADR-012): a floor plan id is operational/editable identity, not the
/// same kind of business identity `OrderIdentityProvider` owns.
abstract interface class FloorPlanIdGenerator {
  String nextFloorPlanId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialFloorPlanIdGenerator implements FloorPlanIdGenerator {
  SequentialFloorPlanIdGenerator({this.prefix = 'floor'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextFloorPlanId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
