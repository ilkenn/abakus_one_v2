/// A courier's real-time availability standing — distinct from
/// [CourierShiftStatus] (a courier can be on an `active` shift while
/// `paused`) and from `CourierRegistryStatus` (registry-level, rarely
/// changes).
enum CourierAvailabilityStatus {
  online,
  offline,
  available,
  temporarilyUnavailable,
  busy,
  paused,
  suspended,
}
