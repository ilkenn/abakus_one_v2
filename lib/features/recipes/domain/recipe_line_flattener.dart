import '../../../core/errors/business_rule_violation.dart';
import '../../inventory/domain/quantity.dart';
import '../data/sub_recipe_repository.dart';
import '../data/sub_recipe_version_repository.dart';
import 'flattened_ingredient_line.dart';
import 'recipe_line.dart';

/// Recursively expands a list of [RecipeLine]s — resolving any nested
/// [SubRecipe] line down to its own raw-ingredient lines — into a flat
/// [FlattenedIngredientLine] list — Phase 7 (`docs/decisions.md`
/// ADR-024). Pure computation: never persists anything, never checks
/// authorization — shared by `ResolveRecipeIngredientSnapshot` (which
/// persists the result as `RecipeIngredientSnapshot` rows) and the
/// Dynamic Bowl Builder resolver (which uses the result transiently,
/// per order, without ever writing a `RecipeIngredientSnapshot` row
/// for it).
///
/// Scaling through nested sub-recipes is carried as an exact
/// numerator/denominator pair through the recursion and only divided
/// once, at each ingredient leaf — avoids compounding floating-point
/// rounding error across nesting levels.
///
/// Detects (and rejects via [RecipeCycleDetectedViolation]) a
/// sub-recipe that transitively references itself, rather than
/// recursing forever.
class RecipeLineFlattener {
  const RecipeLineFlattener({
    required SubRecipeRepository subRecipeRepository,
    required SubRecipeVersionRepository subRecipeVersionRepository,
  })  : _subRecipeRepository = subRecipeRepository,
        _subRecipeVersionRepository = subRecipeVersionRepository;

  final SubRecipeRepository _subRecipeRepository;
  final SubRecipeVersionRepository _subRecipeVersionRepository;

  Future<List<FlattenedIngredientLine>> flatten(List<RecipeLine> lines) async {
    final out = <FlattenedIngredientLine>[];
    await _expand(
      lines: lines,
      scaleNumerator: 1,
      scaleDenominator: 1,
      visitedSubRecipeIds: const {},
      out: out,
    );
    return out;
  }

  Future<void> _expand({
    required List<RecipeLine> lines,
    required int scaleNumerator,
    required int scaleDenominator,
    required Set<String> visitedSubRecipeIds,
    required List<FlattenedIngredientLine> out,
  }) async {
    for (final line in lines) {
      if (line.referencesIngredient) {
        final scaledSmallestUnits =
            (line.quantity.smallestUnits * scaleNumerator) ~/ scaleDenominator;
        out.add(FlattenedIngredientLine(
          line.ingredientId!,
          Quantity(scaledSmallestUnits, line.quantity.unit),
        ));
        continue;
      }

      final subRecipeId = line.subRecipeId!;
      if (visitedSubRecipeIds.contains(subRecipeId)) {
        throw RecipeCycleDetectedViolation(subRecipeId: subRecipeId);
      }

      final subRecipe = await _subRecipeRepository.findById(subRecipeId);
      if (subRecipe == null) {
        throw UnknownRecipeEntityViolation(
          entityName: 'SubRecipe',
          id: subRecipeId,
        );
      }
      final subVersion = await _subRecipeVersionRepository
          .findById(subRecipe.currentVersionId);
      if (subVersion == null) {
        throw UnknownRecipeEntityViolation(
          entityName: 'SubRecipeVersion',
          id: subRecipe.currentVersionId,
        );
      }

      final requestedQuantity = line.quantity;
      final totalYield = subVersion.yieldAmount.totalQuantity;
      if (requestedQuantity.unit != totalYield.unit) {
        throw UnitMismatchViolation(
          expectedUnitCode: totalYield.unit.code,
          actualUnitCode: requestedQuantity.unit.code,
        );
      }

      await _expand(
        lines: subVersion.lines,
        scaleNumerator: scaleNumerator * requestedQuantity.smallestUnits,
        scaleDenominator: scaleDenominator * totalYield.smallestUnits,
        visitedSubRecipeIds: {...visitedSubRecipeIds, subRecipeId},
        out: out,
      );
    }
  }
}
