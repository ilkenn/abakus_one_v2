/// Backend-neutral traffic-adjustment seam for [AdaptiveEtaEstimator] —
/// Sprint 5B Part 5's "traffic multiplier foundation." **Deliberately not
/// a commercial routing/traffic API integration** (none is approved) —
/// implementations here are rule-based heuristics only, always returning a
/// multiplier the caller applies to a naive time estimate (`>= 1.0`, where
/// `1.0` means "no adjustment").
abstract interface class TrafficMultiplierProvider {
  double multiplierFor(DateTime at);
}

/// Honest "no adjustment" default — always `1.0`.
class NoOpTrafficMultiplierProvider implements TrafficMultiplierProvider {
  const NoOpTrafficMultiplierProvider();

  @override
  double multiplierFor(DateTime at) => 1.0;
}

/// A simple, local, non-commercial heuristic: widens the estimate during
/// configured rush-hour windows (by hour-of-day, 0-23, local time) —
/// **never hardcoded**, every window/multiplier is a constructor field so
/// operators can retune per branch/city without a code change. Not real
/// traffic data — an honest, named foundation to build on, not a
/// simulation of one.
class TimeOfDayTrafficMultiplierProvider implements TrafficMultiplierProvider {
  const TimeOfDayTrafficMultiplierProvider({
    this.rushHourWindows = const [
      (startHour: 7, endHour: 9),
      (startHour: 17, endHour: 19),
    ],
    this.rushHourMultiplier = 1.4,
  });

  /// `startHour` inclusive, `endHour` exclusive, both 0-23.
  final List<({int startHour, int endHour})> rushHourWindows;

  /// Applied when [at]'s local hour falls inside any [rushHourWindows]
  /// entry.
  final double rushHourMultiplier;

  @override
  double multiplierFor(DateTime at) {
    final hour = at.hour;
    final isRushHour = rushHourWindows.any(
      (window) => hour >= window.startHour && hour < window.endHour,
    );
    return isRushHour ? rushHourMultiplier : 1.0;
  }
}
