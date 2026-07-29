import '../delivery/delivery_failure_responsibility.dart';

/// A computed, read-only operational metrics summary for one courier over
/// one period — **never persisted as authoritative data**, always
/// rebuildable from the underlying immutable events/records
/// (`docs/decisions.md` ADR-017). Deliberately excludes anything
/// resembling a score, rank, or automatic punishment — "do not implement
/// employee scoring, automatic punishment, payroll, or opaque ranking."
class CourierPerformanceSnapshot {
  const CourierPerformanceSnapshot({
    required this.courierId,
    required this.periodStart,
    required this.periodEnd,
    this.assignmentsOffered = 0,
    this.assignmentsAccepted = 0,
    this.assignmentsRejected = 0,
    this.averagePickupDurationSeconds,
    this.averageRestaurantWaitSeconds,
    this.averageDeliveryDurationSeconds,
    this.successfulDeliveries = 0,
    this.failedByResponsibility = const {},
    this.reassignmentCount = 0,
    this.geofenceOverrideCount = 0,
    this.customerContactAttempts = 0,
    this.activeShiftDuration = Duration.zero,
    this.packagesDelivered = 0,
  });

  final String courierId;
  final DateTime periodStart;
  final DateTime periodEnd;

  final int assignmentsOffered;
  final int assignmentsAccepted;
  final int assignmentsRejected;

  final double? averagePickupDurationSeconds;
  final double? averageRestaurantWaitSeconds;
  final double? averageDeliveryDurationSeconds;

  final int successfulDeliveries;

  /// Distinguishes customer-caused, restaurant-caused, courier-caused,
  /// system-caused, and force-majeure delays/failures — the explicit
  /// requirement that performance data never conflate these.
  final Map<DeliveryFailureResponsibility, int> failedByResponsibility;

  final int reassignmentCount;
  final int geofenceOverrideCount;
  final int customerContactAttempts;
  final Duration activeShiftDuration;
  final int packagesDelivered;
}
