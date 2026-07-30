import '../compensation/courier_earnings_summary.dart';
import 'courier_performance_snapshot.dart';

/// The manager-facing "Performance card" for one courier over one period —
/// Sprint 5C Part 10. **Composes the two already-existing read-models
/// rather than recomputing anything**: [performance] is an unmodified
/// [CourierPerformanceSnapshot] (deliveries/durations/wait/rejections/
/// failures/active-shift-duration), [earnings] is an unmodified
/// [CourierEarningsSummary] (the earnings breakdown). Never persisted
/// itself, rebuildable at any time from the same underlying records both
/// already read from.
///
/// **Honest gap, not an oversight**: the brief's "customer rating" field
/// has no data source anywhere in the app — no rating is ever collected
/// from a customer today, and [CourierPerformanceSnapshot]'s own doc
/// comment explicitly excludes any score/rank field by design ("do not
/// implement employee scoring... or opaque ranking"). This type carries
/// no rating field; fabricating one would violate that same rule.
class CourierPerformanceCard {
  const CourierPerformanceCard({
    required this.courierId,
    required this.periodStart,
    required this.periodEnd,
    required this.performance,
    required this.earnings,
  });

  final String courierId;
  final DateTime periodStart;
  final DateTime periodEnd;

  final CourierPerformanceSnapshot performance;
  final CourierEarningsSummary earnings;

  /// Sum of every [CourierPerformanceSnapshot.failedByResponsibility]
  /// count — "cancelled" is not a separately-tracked concept anywhere in
  /// the courier feature, so this reuses the existing failure-
  /// responsibility breakdown rather than inventing a new counter.
  int get cancelledDeliveries =>
      performance.failedByResponsibility.values.fold(0, (a, b) => a + b);
}
