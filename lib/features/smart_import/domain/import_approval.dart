import 'import_review_decision.dart';

/// The reviewer's complete decision set for one [ImportDraft] — Phase 7
/// (`docs/decisions.md` ADR-024). Produced by `ApproveImportDraft`,
/// consumed by `CommitImportDraft` — the one and only input that
/// determines what `CommitImportDraft` is allowed to write; a
/// [ParsedProduct]/[ParsedCategory] with no corresponding
/// [ImportReviewOutcome.approved] decision here is never committed.
class ImportApproval {
  const ImportApproval({
    required this.importJobId,
    required this.approvedByStaffId,
    required this.approvedAt,
    this.decisions = const [],
  });

  final String importJobId;
  final String approvedByStaffId;
  final DateTime approvedAt;
  final List<ImportReviewDecision> decisions;
}
