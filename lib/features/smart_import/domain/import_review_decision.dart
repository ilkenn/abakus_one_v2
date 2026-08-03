/// What a reviewer decided about one parsed entity (a `ParsedCategory`/
/// `ParsedProduct`/`ParsedIngredientSuggestion`/`ParsedRecipeSuggestion`,
/// referenced by its `tempId`) — Phase 7 (`docs/decisions.md` ADR-024).
enum ImportReviewOutcome { approved, rejected }

class ImportReviewDecision {
  const ImportReviewDecision({
    required this.tempId,
    required this.outcome,
    this.editedName,
    this.editedPrice,
  });

  final String tempId;
  final ImportReviewOutcome outcome;

  /// Non-null only if the reviewer corrected the name before approving —
  /// "the user must approve before authoritative records are created,"
  /// which includes approving *edited* content, never just raw parse
  /// output.
  final String? editedName;

  final double? editedPrice;
}
