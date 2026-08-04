/// The evaluated state of one [StoreComplianceCriterion] — Phase 8Q
/// (`docs/decisions.md` ADR-025), "Store Compliance Foundation."
/// Deliberately a separate enum from [ReleaseReadinessCriterionStatus]
/// even though its 3 values are identical in shape — release-process
/// readiness and app-store policy compliance are different concerns
/// with different owners, mirroring this phase's own "per-bounded-
/// context separate types, never shared" precedent (established for
/// its audit-entry types).
enum StoreComplianceCriterionStatus {
  /// Genuinely satisfied today, verified against real code — never
  /// asserted optimistically.
  ready,

  /// Not satisfied — a real gap, not a formality.
  notReady,

  /// The code-level foundation exists, but a non-code action (a store-
  /// console declaration, a published legal document) still has to be
  /// performed before this criterion is actually satisfied.
  manualStepRequired,
}
