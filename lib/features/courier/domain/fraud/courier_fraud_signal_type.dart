/// The full Sprint 5B Part 8 fraud-signal taxonomy. **Operational signals
/// only — nothing in this feature reads this enum to block, punish, or
/// gate any courier action.** Signals feed a future Risk Engine
/// (out of scope this sprint); this feature's only responsibility is to
/// generate and record them honestly.
///
/// Six of these ten values have a real detector this sprint
/// ([CourierFraudSignalDetector]/`DetectCourierFraudSignals`/
/// `DetectRepeatedLocationLossSignal`) because a real underlying data
/// source exists for them. The remaining four —
/// [developerModeEnabled], [timeManipulationSuspected],
/// [locationSpoofSuspicion], [batteryOptimizationAbuseSuspected] — are
/// defined here for taxonomy completeness only. **No detector exists for
/// them this sprint**: there is no developer-mode-detection API, clock-
/// skew-detection mechanism, spoofing-app-detection signal, or battery-
/// optimization-allowlist-status API wired into this app. Presenting a
/// fabricated detector for any of these would be worse than an honest
/// gap — flagged explicitly in the Sprint 5B report as future work, not
/// silently assumed unnecessary.
enum CourierFraudSignalType {
  /// Real detector: [CourierFraudSignalDetector.detectImpossibleSpeed].
  impossibleSpeed,

  /// Real detector: [CourierFraudSignalDetector.detectGpsJump].
  gpsJump,

  /// Real detector: [CourierFraudSignalDetector.detectMockLocation] (reads
  /// [CourierLocationSnapshot.isMocked] — Android-only signal, see that
  /// field's own doc comment for the honest iOS gap).
  mockLocationDetected,

  /// No detector this sprint — see class doc.
  developerModeEnabled,

  /// No detector this sprint — see class doc.
  timeManipulationSuspected,

  /// No detector this sprint — see class doc.
  locationSpoofSuspicion,

  /// Real detector: `DetectRepeatedLocationLossSignal`, counting
  /// [LocationUnavailableReason.signalLost] occurrences in
  /// `CourierLocationAvailability` history within a window.
  repeatedGpsLoss,

  /// Real detector: [CourierFraudSignalDetector.detectUnrealisticTravel].
  unrealisticTravelDistance,

  /// Real detector: `DetectRepeatedLocationLossSignal`, from
  /// [LocationUnavailableReason.backgroundBlocked].
  backgroundTrackingDisabled,

  /// No detector this sprint — see class doc.
  batteryOptimizationAbuseSuspected,
}
