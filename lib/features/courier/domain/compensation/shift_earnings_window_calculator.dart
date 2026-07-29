/// Determines the exact `[start, end)` window over which a
/// [CourierShift]'s hourly earnings accrue — a pure function, no I/O,
/// mirrors `DispatchScorer`/`GeofenceEvaluator`'s shape.
abstract final class ShiftEarningsWindowCalculator {
  ShiftEarningsWindowCalculator._();

  /// "Hourly earnings begin at `MAX(ScheduledShiftStart, ActualCourierLogin)`."
  /// Early arrival never creates extra earnings; late arrival reduces
  /// payable hours.
  static DateTime determineStartAt({
    required DateTime scheduledStart,
    required DateTime actualLogin,
  }) {
    return scheduledStart.isAfter(actualLogin) ? scheduledStart : actualLogin;
  }

  /// "If no active delivery exists, hourly earnings stop at scheduled
  /// shift end. If the courier is delivering the final package, hourly
  /// earnings stop at the first verified customer-geofence arrival — not
  /// at delivery confirmation." [finalDeliveryVerifiedArrivalAt] is the
  /// caller-supplied result of that geofence-arrival lookup
  /// (`FirstVerifiedGeofenceArrivalFinder`) for whichever delivery was
  /// still active at [scheduledEnd] — `null` when no such delivery
  /// existed, in which case [scheduledEnd] is used directly.
  static DateTime determineEndAt({
    required DateTime scheduledEnd,
    DateTime? finalDeliveryVerifiedArrivalAt,
  }) {
    return finalDeliveryVerifiedArrivalAt ?? scheduledEnd;
  }

  /// `end - start`, floored at [Duration.zero] — a shift whose computed
  /// end precedes its own computed start (e.g. the courier never actually
  /// logged in) pays zero hours, never a negative duration.
  static Duration payableDuration({
    required DateTime start,
    required DateTime end,
  }) {
    final duration = end.difference(start);
    return duration.isNegative ? Duration.zero : duration;
  }
}
