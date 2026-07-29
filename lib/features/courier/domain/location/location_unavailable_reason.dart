/// Why a courier's device-reported location became unavailable — the
/// predefined reason recorded on [CourierLocationAvailability] and its
/// audit trail. No free-text reason field exists (Sprint 5B REQUIRED
/// business-rule correction).
enum LocationUnavailableReason {
  permissionDenied,
  permissionRestricted,
  serviceDisabled,
  backgroundBlocked,
  signalLost,
}
