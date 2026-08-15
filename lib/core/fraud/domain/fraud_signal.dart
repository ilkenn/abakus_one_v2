/// One descriptive fraud-relevant observation about a `FraudEvidence`
/// record — FRAUD-F.0. Immutable, append-only.
///
/// **Deliberately carries no enforcement field of any kind** — no
/// `blocked`, `rejectOrder`, `banCustomer`, `severity`-driven action,
/// nothing a caller could wire into an automatic block/ban/deny decision.
/// Mirrors `CourierFraudSignal`'s own "generate operational signals only,
/// do NOT implement punishment" discipline
/// (`lib/features/courier/domain/fraud/courier_fraud_signal.dart`) — this
/// type is a deliberately separate, parallel construct, not a migration of
/// that one (courier's fraud-signal migration is explicitly out of scope
/// for FRAUD-F.0, per `docs/decisions.md`).
class FraudSignal {
  const FraudSignal({
    required this.id,
    required this.evidenceId,
    required this.type,
    required this.description,
    required this.detectedAt,
  });

  final String id;
  final String evidenceId;

  /// Free-text signal category (e.g. a future `'distance_mismatch'`) —
  /// deliberately not a closed enum yet: FRAUD-F.0 defines no real
  /// detectors and no permanent risk thresholds (see the approved
  /// architecture's "no permanent thresholds in this phase" rule), and
  /// fabricating a taxonomy with no detector behind any value would repeat
  /// the exact anti-pattern `CourierFraudSignalType`'s own doc comment
  /// warns against. A closed enum can be introduced once a real detector
  /// exists to justify each value.
  final String type;

  final String description;
  final DateTime detectedAt;
}
