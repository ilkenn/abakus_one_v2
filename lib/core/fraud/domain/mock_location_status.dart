/// Whether the platform's own mock-location signal fired for a captured
/// device location — FRAUD-F.0. **Never a binary "is this location
/// genuine" verdict** — see each value's own doc comment.
enum MockLocationStatus {
  /// The platform reported this reading as mocked/simulated (e.g.
  /// Android's `Location.isMock`).
  detected,

  /// The platform did not report the reading as mocked. **This does not
  /// mean the location is genuine** — it only means the one detector this
  /// platform exposes did not fire. A more sophisticated spoofing
  /// technique may go entirely undetected. No caller in this codebase may
  /// treat [notDetected] as proof of a real location.
  notDetected,

  /// This platform exposes no mock-location signal at all (iOS has no
  /// `Location.isMock` equivalent) — an honest, permanent platform gap,
  /// never a false [notDetected]. Mirrors
  /// `CourierLocationSnapshot.isMocked`'s own documented iOS gap
  /// (`lib/features/courier/domain/location/courier_location_snapshot.dart`).
  unsupported,

  /// A mock-location signal exists on this platform in principle, but
  /// this specific reading did not carry one (e.g. the underlying
  /// location plugin failed to report it for this call).
  unavailable,
}
