/// An immutable, versioned server interpretation of one or more
/// `FraudEvidence`/`FraudSignal` records for a specific order — FRAUD-F.0.
/// Reserved for FRAUD-F.2 (order-submit evidence integration, not
/// started): no production code constructs one yet. Never mutated after
/// creation, and creating one never mutates any evidence it references via
/// [priorEvidenceId] — see `FraudEvidence`'s own doc comment on that same
/// rule.
class FraudRiskContext {
  const FraudRiskContext({
    required this.id,
    required this.orderId,
    required this.evidenceIds,
    required this.signalIds,
    this.priorEvidenceId,
    required this.policyVersion,
    required this.createdAt,
  });

  final String id;
  final String orderId;
  final List<String> evidenceIds;
  final List<String> signalIds;

  /// The `FraudEvidence.id` of the address-save evidence this order's
  /// address originated from, if one exists. `null` when the customer's
  /// saved address predates FRAUD-F.1 or was never captured with
  /// evidence.
  final String? priorEvidenceId;

  /// Which version of the (not-yet-defined) risk-derivation policy
  /// produced this context — FRAUD-F.0 deliberately defines no real
  /// policy or thresholds; distance mismatch alone must never be treated
  /// as automatic order rejection, in any version.
  final String policyVersion;

  final DateTime createdAt;
}
