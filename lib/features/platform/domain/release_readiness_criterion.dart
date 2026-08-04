import 'release_readiness_criterion_status.dart';

/// One evaluated item in a [ReleaseReadinessSnapshot] — Phase 8P
/// (`docs/decisions.md` ADR-025). Mirrors `PlatformMonitoringSnapshot
/// .dormantServiceNotes`' "honest, factual, never glossed over"
/// principle, but structured (key/label/status) instead of free text,
/// so a future release-checklist UI can render it as a real checklist
/// rather than a paragraph.
class ReleaseReadinessCriterion {
  const ReleaseReadinessCriterion({
    required this.key,
    required this.label,
    required this.status,
    required this.note,
  });

  /// A stable, code-facing identifier — never shown to a user directly.
  final String key;

  /// A short, human-readable label for this criterion.
  final String label;

  final ReleaseReadinessCriterionStatus status;

  /// The concrete, evidence-backed reason for [status] — never a vague
  /// placeholder like "TODO" or "pending."
  final String note;
}
