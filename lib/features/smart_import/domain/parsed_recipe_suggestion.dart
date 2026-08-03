import 'import_confidence.dart';

/// A suggestion that a `Recipe` (Phase 7G) should exist for a parsed
/// product, composed of the given ingredient-suggestion `tempId`s —
/// Phase 7 (`docs/decisions.md` ADR-024). Like
/// `ParsedIngredientSuggestion`, purely advisory — never creates a
/// `Recipe` until the reviewer approves it.
class ParsedRecipeSuggestion {
  const ParsedRecipeSuggestion({
    required this.tempId,
    required this.sourceProductTempId,
    this.suggestedIngredientTempIds = const [],
    required this.confidence,
  });

  final String tempId;
  final String sourceProductTempId;
  final List<String> suggestedIngredientTempIds;
  final ImportConfidence confidence;
}
