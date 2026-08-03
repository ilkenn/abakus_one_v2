import 'import_confidence.dart';

/// A suggestion that an ingredient with [suggestedName] should exist in
/// the tenant's `Ingredient` catalog (Phase 7F), inferred from a parsed
/// product's name/description/modifiers — Phase 7
/// (`docs/decisions.md` ADR-024). Never creates an `Ingredient`
/// automatically — `CommitImportDraft` only creates one for a
/// suggestion the reviewer explicitly approved (`ImportReviewDecision`).
class ParsedIngredientSuggestion {
  const ParsedIngredientSuggestion({
    required this.tempId,
    required this.suggestedName,
    required this.sourceProductTempId,
    required this.confidence,
  });

  final String tempId;
  final String suggestedName;
  final String sourceProductTempId;
  final ImportConfidence confidence;
}
