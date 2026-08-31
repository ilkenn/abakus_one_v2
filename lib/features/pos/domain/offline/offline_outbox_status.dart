/// Lifecycle status of one [OfflineQueuedCashPayment] — mirrors the
/// governing AP-4 outbox contract exactly: `localPending -> transmitted ->
/// serverAcknowledged/reconciled`, plus the explicit failure states,
/// renamed to this feature's own vocabulary (`pending`/`syncing`/`synced`/
/// `failed`/`manualInterventionRequired`) to match this codebase's existing
/// `CashSessionStatus`/`PaymentAttemptStatus`-style naming.
enum OfflineOutboxStatus {
  /// Captured locally, not yet attempted against the real backend.
  pending,

  /// A sync attempt is currently in flight for this entry.
  syncing,

  /// The backend accepted it — `recordPaymentAttempt` returned `succeeded`.
  synced,

  /// The backend rejected it for a reason that will never resolve by
  /// itself (e.g. the lease was revoked, or conservation was violated) —
  /// requires staff/manager attention, never silently retried forever.
  failed,

  /// The sync attempt itself failed in a way whose outcome is unknown
  /// (e.g. the connection dropped mid-request) — must NOT be silently
  /// retried as a fresh charge; requires reconciliation before either
  /// retrying or discarding.
  manualInterventionRequired,
}
