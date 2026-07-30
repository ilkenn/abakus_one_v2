/// The branch's overall operational health — Sprint 5C Part 13, the
/// brief's own 🟢🟡🔴 traffic-light indicator. Kept as three named levels
/// here; mapping to emoji/color is a presentation-layer concern only
/// (mirrors `CourierStatusLabels`'s existing domain/presentation split).
enum CourierOperationHealthLevel {
  /// 🟢 — no signal crossed even the lower ("degraded") threshold.
  healthy,

  /// 🟡 — at least one signal crossed its "degraded" threshold, but none
  /// reached "critical".
  degraded,

  /// 🔴 — at least one signal crossed its "critical" threshold.
  critical,
}
