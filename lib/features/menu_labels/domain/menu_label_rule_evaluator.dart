import '../../allergens/domain/allergen_declaration_status.dart';
import '../../allergens/domain/allergen_type.dart';
import '../../allergens/domain/ingredient_allergen_declaration.dart';
import '../../nutrition/domain/nutrition_calculation_result.dart';
import '../../recipes/domain/recipe_calculation_status.dart';
import 'menu_label_rule.dart';
import 'menu_label_type.dart';

class MenuLabelEvaluationResult {
  const MenuLabelEvaluationResult({
    required this.qualifies,
    required this.evidenceSummary,
  });

  final bool qualifies;
  final String evidenceSummary;
}

/// Pure, synchronous evaluation of one [MenuLabelRule] against a
/// recipe's already-computed nutrition/allergen data — Phase 7
/// (`docs/decisions.md` ADR-024). No I/O of its own — the caller
/// (`EvaluateMenuLabelSuggestions`) fetches everything needed first.
///
/// A nutrition-threshold rule never qualifies unless [nutritionResult]
/// exists **and** its `status` is [RecipeCalculationStatus.calculated]
/// (never `incomplete`) — "no automatic legal compliance claims" means
/// this never guesses from partial data. A free-from rule never
/// qualifies unless *every* [ingredientIds] entry has a **confirmed**
/// ([IngredientAllergenDeclaration.isConfirmedByHuman]) declaration of
/// exactly [AllergenDeclarationStatus.explicitlyFreeFrom] for the
/// target allergen — "free from labels require verified evidence,"
/// missing/unknown/unconfirmed data is never treated as "presumed
/// free."
class MenuLabelRuleEvaluator {
  const MenuLabelRuleEvaluator();

  MenuLabelEvaluationResult evaluate({
    required MenuLabelRule rule,
    NutritionCalculationResult? nutritionResult,
    required List<String> ingredientIds,
    required Map<String, List<IngredientAllergenDeclaration>>
        allergenDeclarationsByIngredientId,
  }) {
    switch (rule.labelType) {
      case MenuLabelType.highProtein:
        return _nutrientThreshold(
          value: nutritionResult?.perPortionValues.proteinMilligrams,
          status: nutritionResult?.status,
          threshold: rule.thresholdMilligramsOrKcal,
          requireAtLeast: true,
          unitLabel: 'mg protein/porsiyon',
        );
      case MenuLabelType.lowCalorie:
        return _nutrientThreshold(
          value: nutritionResult?.perPortionValues.energyKcal,
          status: nutritionResult?.status,
          threshold: rule.thresholdMilligramsOrKcal,
          requireAtLeast: false,
          unitLabel: 'kcal/porsiyon',
        );
      case MenuLabelType.highFiber:
        return _nutrientThreshold(
          value: nutritionResult?.perPortionValues.fiberMilligrams,
          status: nutritionResult?.status,
          threshold: rule.thresholdMilligramsOrKcal,
          requireAtLeast: true,
          unitLabel: 'mg lif/porsiyon',
        );
      case MenuLabelType.glutenFree:
      case MenuLabelType.lactoseFree:
        final allergenType = rule.freeFromAllergenType;
        if (allergenType == null) {
          return const MenuLabelEvaluationResult(
            qualifies: false,
            evidenceSummary: 'Kural için hedef alerjen tanımlı değil',
          );
        }
        return _freeFrom(
          allergenType: allergenType,
          ingredientIds: ingredientIds,
          declarationsByIngredientId: allergenDeclarationsByIngredientId,
        );
      case MenuLabelType.vegan:
      case MenuLabelType.vegetarian:
      case MenuLabelType.spicy:
      case MenuLabelType.athleteFriendly:
        return const MenuLabelEvaluationResult(
          qualifies: false,
          evidenceSummary:
              'Bu etiket için bu fazda otomatik değerlendirme desteklenmiyor',
        );
    }
  }

  MenuLabelEvaluationResult _nutrientThreshold({
    required int? value,
    required RecipeCalculationStatus? status,
    required int? threshold,
    required bool requireAtLeast,
    required String unitLabel,
  }) {
    if (status != RecipeCalculationStatus.calculated ||
        value == null ||
        threshold == null) {
      return MenuLabelEvaluationResult(
        qualifies: false,
        evidenceSummary:
            'Besin değeri hesaplaması eksik veya yapılmamış ($unitLabel)',
      );
    }
    final qualifies = requireAtLeast ? value >= threshold : value <= threshold;
    final comparator = requireAtLeast ? '>=' : '<=';
    return MenuLabelEvaluationResult(
      qualifies: qualifies,
      evidenceSummary: '$value $unitLabel $comparator $threshold eşiği',
    );
  }

  MenuLabelEvaluationResult _freeFrom({
    required AllergenType allergenType,
    required List<String> ingredientIds,
    required Map<String, List<IngredientAllergenDeclaration>>
        declarationsByIngredientId,
  }) {
    if (ingredientIds.isEmpty) {
      return const MenuLabelEvaluationResult(
        qualifies: false,
        evidenceSummary: 'Değerlendirilecek malzeme yok',
      );
    }
    for (final ingredientId in ingredientIds) {
      final declarations = declarationsByIngredientId[ingredientId] ?? const [];
      final hasVerifiedFreeFrom = declarations.any((d) =>
          d.allergenType == allergenType &&
          d.status == AllergenDeclarationStatus.explicitlyFreeFrom &&
          d.isConfirmedByHuman);
      if (!hasVerifiedFreeFrom) {
        return MenuLabelEvaluationResult(
          qualifies: false,
          evidenceSummary:
              'Malzeme "$ingredientId" için doğrulanmış "içermez" kaydı yok',
        );
      }
    }
    return MenuLabelEvaluationResult(
      qualifies: true,
      evidenceSummary:
          '${ingredientIds.length} malzemenin tamamı için doğrulanmış '
          '"içermez" kaydı mevcut',
    );
  }
}
