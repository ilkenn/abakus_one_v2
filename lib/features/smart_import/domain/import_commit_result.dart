/// The result of actually writing an [ImportApproval]'s approved
/// entities through existing domain use cases — Phase 7
/// (`docs/decisions.md` ADR-024). The one and only point in the whole
/// Smart Import flow where a real `MenuCategory`/`MenuProduct`/
/// `Ingredient` gets created.
class ImportCommitResult {
  const ImportCommitResult({
    required this.importJobId,
    this.createdCategoryIds = const [],
    this.createdProductIds = const [],
    this.createdIngredientIds = const [],
    this.skippedCount = 0,
    this.errorCount = 0,
    required this.committedAt,
  });

  final String importJobId;
  final List<String> createdCategoryIds;
  final List<String> createdProductIds;
  final List<String> createdIngredientIds;

  /// Parsed entities with no matching approved [ImportReviewDecision] —
  /// never committed, counted here so the summary is honest about what
  /// was left out, not just what was created.
  final int skippedCount;

  final int errorCount;
  final DateTime committedAt;
}
