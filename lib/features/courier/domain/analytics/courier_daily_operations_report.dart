import '../performance/courier_performance_snapshot.dart';

/// The manager-facing daily analytics report for one branch — Sprint 5C
/// Part 12. Aggregates already-real, already-populated data only:
/// [totalDeliveries]/[averageDeliveryDurationSeconds]/[peakHour] are
/// computed directly from `Delivery.createdAt`/`.deliveredAt`,
/// [totalDistanceTravelledKm] sums `DeliveryEarnings.distanceKm`, and
/// [courierPerformance] reuses the unmodified `CourierPerformanceSnapshot`
/// per courier.
///
/// **Two of the brief's requested fields are deliberately absent, not
/// forgotten**:
/// - *Average ETA*: `DeliveryRouteSnapshot.etaMinutes` exists as a domain
///   field, but no repository ever persists it anywhere in this codebase
///   — `NaiveEtaEstimator`/`AdaptiveEtaEstimator` produce it transiently
///   for in-the-moment UI display only. There is nothing to aggregate.
/// - *Peak region*: no region/district/neighbourhood taxonomy exists
///   anywhere in the app — the only delivery-destination data is
///   `Order.deliveryAddressText`, free text with no verified boundaries.
///   Bucketing by raw address text and calling the result a "region"
///   would misrepresent street-level noise as a geographic aggregate.
///
/// Fabricating either would violate the explicit "never invent missing
/// behavior" instruction — both are flagged here for a human decision on
/// whether to build the missing persistence/taxonomy first.
class CourierDailyOperationsReport {
  const CourierDailyOperationsReport({
    required this.branchId,
    required this.periodStart,
    required this.periodEnd,
    required this.totalDeliveries,
    required this.totalDistanceTravelledKm,
    this.averageDeliveryDurationSeconds,
    this.peakHour,
    required this.courierPerformance,
  });

  final String branchId;

  /// The reported day's `[periodStart, periodEnd)` window — local
  /// midnight to the next local midnight.
  final DateTime periodStart;
  final DateTime periodEnd;

  /// Count of deliveries with `DeliveryStatus.delivered` and a
  /// `deliveredAt` inside the period.
  final int totalDeliveries;

  final double totalDistanceTravelledKm;

  /// Mean `deliveredAt - createdAt` across [totalDeliveries], in seconds.
  /// `null` when [totalDeliveries] is zero.
  final double? averageDeliveryDurationSeconds;

  /// The local hour (0-23) with the most `deliveredAt` timestamps.
  /// `null` when [totalDeliveries] is zero.
  final int? peakHour;

  /// One [CourierPerformanceSnapshot] per courier eligible for the
  /// branch, for the same period — never a score/rank, matching that
  /// type's own documented exclusion.
  final List<CourierPerformanceSnapshot> courierPerformance;
}
