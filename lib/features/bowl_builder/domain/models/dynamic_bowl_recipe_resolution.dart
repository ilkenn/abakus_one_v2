import '../../../recipes/domain/flattened_ingredient_line.dart';

/// The pure-computation result of `ResolveDynamicBowlRecipe` — Phase 7
/// (`docs/decisions.md` ADR-024). Transient: never persisted directly;
/// `CreateBowlBuilderRecipeSnapshot` turns it into a
/// [BowlBuilderRecipeSnapshot]'s [BowlBuilderResolvedIngredientLine]s.
class DynamicBowlRecipeResolution {
  const DynamicBowlRecipeResolution({
    this.baseRecipeVersionId,
    required this.resolvedLines,
  });

  final String? baseRecipeVersionId;
  final List<FlattenedIngredientLine> resolvedLines;
}
