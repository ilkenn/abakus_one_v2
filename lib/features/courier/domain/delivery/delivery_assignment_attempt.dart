/// One immutable, append-only log entry of a single dispatch attempt for a
/// [Delivery] — distinct from [DeliveryAssignment] (the current offer
/// state): this is the permanent history of *every* attempt, including
/// ones superseded by reassignment, carrying the scoring inputs that
/// produced it (for later review/debugging of dispatch decisions, never
/// for automatic courier scoring/punishment — see `CourierPerformanceSnapshot`'s
/// own doc comment on that same boundary).
class DeliveryAssignmentAttempt {
  const DeliveryAssignmentAttempt({
    required this.id,
    required this.deliveryId,
    required this.assignmentId,
    required this.courierId,
    this.scoringSnapshot = const {},
    required this.attemptedAt,
  });

  final String id;
  final String deliveryId;
  final String assignmentId;
  final String courierId;

  /// The scoring inputs/weights that produced this attempt — e.g.
  /// `{'distanceScore': 0.8, 'capacityScore': 1.0}` — a frozen snapshot,
  /// never recomputed after the fact.
  final Map<String, double> scoringSnapshot;

  final DateTime attemptedAt;
}
