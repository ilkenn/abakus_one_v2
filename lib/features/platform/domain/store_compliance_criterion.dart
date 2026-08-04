import 'store_compliance_criterion_status.dart';

/// One evaluated item in a [StoreComplianceSnapshot] — Phase 8Q
/// (`docs/decisions.md` ADR-025). Structured (key/label/status) rather
/// than free text, so a future compliance-checklist UI can render it
/// as a real checklist rather than a paragraph — mirrors
/// `ReleaseReadinessCriterion`'s shape exactly, kept as a distinct
/// type per this phase's separate-bounded-context precedent.
class StoreComplianceCriterion {
  const StoreComplianceCriterion({
    required this.key,
    required this.label,
    required this.status,
    required this.note,
  });

  /// A stable, code-facing identifier — never shown to a user directly.
  final String key;

  /// A short, human-readable label for this criterion.
  final String label;

  final StoreComplianceCriterionStatus status;

  /// The concrete, evidence-backed reason for [status] — never a vague
  /// placeholder like "TODO" or "pending."
  final String note;
}
