/// Whether usable device-location evidence was actually captured for a
/// `FraudEvidence` record — FRAUD-F.1. The server decides this, not the
/// client — see `FraudEvidence`'s own doc comment.
enum FraudEvidenceAvailability {
  /// A usable client location candidate was captured and validated.
  /// `FraudEvidence.clientLocation` is non-null.
  available,

  /// No location candidate exists at all — permission denied, location
  /// services disabled, a capture timeout/error, or the client simply
  /// didn't supply one. `FraudEvidence.clientLocation` is `null`. Address
  /// save still proceeds; this state is itself the evidence.
  unavailable,

  /// A candidate was supplied but could not be trusted as-is (missing or
  /// malformed required fields) — distinct from [unavailable] so a future
  /// reviewer can tell "nothing was ever offered" apart from "something
  /// was offered but didn't hold up." `FraudEvidence.clientLocation` is
  /// `null`.
  incomplete,
}
