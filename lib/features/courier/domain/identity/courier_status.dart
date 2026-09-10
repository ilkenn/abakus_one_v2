/// AP-6 Sprint 2 — a courier's current real-time dispatch standing: is this
/// courier free to hand a new order to right now?
///
/// **Deliberately a new, separate concept from two existing, similarly-named
/// fields on/near [Courier]** — never conflated with either:
/// - `CourierRegistryStatus` (`active`/`suspended`/`archived`) — employment/
///   registry status, rarely changes, orthogonal to whether this courier
///   happens to be out on a delivery right now.
/// - `CourierAvailabilityStatus` (`domain/availability/`) — a heavier,
///   shift-gated, revision-tracked aggregate (`CourierAvailability`, keyed
///   by `(courierId, shiftId)`, requires an active `CourierShift` to reach
///   `available`). This sprint's dispatch flow has no shift concept at
///   all — [CourierStatus] is a plain, directly-settable field, not backed
///   by that subsystem.
enum CourierStatus {
  /// At the branch, no active deliveries, eligible for FIFO assignment.
  available,

  /// Currently out on one or more deliveries (`Courier.activeOrderIds` is
  /// non-empty).
  delivering,

  /// Off-shift / not currently dispatchable — the default for a freshly
  /// registered courier.
  offline,
}
