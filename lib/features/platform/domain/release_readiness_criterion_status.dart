/// The evaluated state of one [ReleaseReadinessCriterion] — Phase 8P
/// (`docs/decisions.md` ADR-025), "Release Readiness Foundation."
enum ReleaseReadinessCriterionStatus {
  /// The criterion is genuinely satisfied today, verified against real
  /// code — never asserted optimistically.
  ready,

  /// The criterion is not satisfied — a real gap, not a formality.
  notReady,

  /// The code-level foundation exists, but a non-code action (e.g. a
  /// Firebase console value, a store-listing field) still has to be
  /// performed before this criterion is actually satisfied.
  manualStepRequired,
}
