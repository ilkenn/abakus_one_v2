/// Sprint 9G (`docs/decisions.md` ADR-026). Mirrors
/// `docs/firestore_data_model.md`'s `deletionRequests/{requestId}`
/// collection shape — `pendingVerification` is the one status a client
/// may create a document in; every later transition is
/// server-authoritative (`firestore.rules`: `allow update: if false` for
/// clients).
///
/// [pendingVerification] exists as its own named state for a future,
/// stronger re-verification flow (e.g. re-entering an OTP before a
/// request is accepted) — this sprint's [RequestAccountDeletion]
/// transitions straight through it into [coolingOff] within the same
/// call, since the caller must already hold a valid authenticated
/// session to reach this use case at all (that session is this sprint's
/// identity verification). [cancelled]/[completed] are terminal.
enum AccountDeletionStatus {
  pendingVerification,
  coolingOff,
  cancelled,
  completed,
}

/// One customer's account-deletion request — keyed by the canonical
/// [uid] (`AuthSession.uid`, `docs/decisions.md` ADR-026 Decision 3), the
/// same identity `Customer.id`/`ProfileModel.id` already key by.
class AccountDeletionRequest {
  const AccountDeletionRequest({
    required this.id,
    required this.uid,
    required this.status,
    required this.requestedAt,
    required this.coolingOffEndsAt,
    this.cancelledAt,
    this.completedAt,
    required this.revision,
  });

  final String id;
  final String uid;
  final AccountDeletionStatus status;
  final DateTime requestedAt;
  final DateTime coolingOffEndsAt;
  final DateTime? cancelledAt;
  final DateTime? completedAt;
  final int revision;

  /// "Request cancellable after identity verification" — the *window*
  /// check only; the caller is still responsible for re-verifying
  /// identity before calling `CancelAccountDeletionRequest`. Takes [now]
  /// explicitly (mirrors [isDue]) rather than reading `DateTime.now()`
  /// internally, so callers/tests control time deterministically.
  bool canCancelAt(DateTime now) =>
      status == AccountDeletionStatus.coolingOff &&
      now.isBefore(coolingOffEndsAt);

  /// Whether the cooling-off window has elapsed and this request is
  /// ready for `ProcessAccountDeletion` (or the equivalent Cloud
  /// Function) to act on.
  bool isDue(DateTime now) =>
      status == AccountDeletionStatus.coolingOff &&
      !now.isBefore(coolingOffEndsAt);

  AccountDeletionRequest copyWith({
    AccountDeletionStatus? status,
    DateTime? cancelledAt,
    bool clearCancelledAt = false,
    DateTime? completedAt,
    bool clearCompletedAt = false,
    required int revision,
  }) {
    return AccountDeletionRequest(
      id: id,
      uid: uid,
      status: status ?? this.status,
      requestedAt: requestedAt,
      coolingOffEndsAt: coolingOffEndsAt,
      cancelledAt: clearCancelledAt ? null : (cancelledAt ?? this.cancelledAt),
      completedAt: clearCompletedAt ? null : (completedAt ?? this.completedAt),
      revision: revision,
    );
  }
}
