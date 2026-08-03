import 'package:abakus_one_v2/features/allergens/domain/allergen_declaration_status.dart';
import 'package:abakus_one_v2/features/allergens/domain/allergen_source_type.dart';
import 'package:abakus_one_v2/features/allergens/domain/allergen_type.dart';
import 'package:abakus_one_v2/features/allergens/domain/allergen_confidence.dart';
import 'package:abakus_one_v2/features/allergens/domain/ingredient_allergen_declaration.dart';
import 'package:abakus_one_v2/features/menu_labels/domain/menu_label_rule.dart';
import 'package:abakus_one_v2/features/menu_labels/domain/menu_label_rule_evaluator.dart';
import 'package:abakus_one_v2/features/menu_labels/domain/menu_label_type.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_calculation_result.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_confidence.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_value_set.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_calculation_status.dart';
import 'package:flutter_test/flutter_test.dart';

MenuLabelRule _rule({
  required MenuLabelType labelType,
  int? threshold,
  AllergenType? freeFromAllergenType,
}) {
  return MenuLabelRule(
    id: 'rule-1',
    organizationId: 'org-1',
    labelType: labelType,
    ruleVersion: 1,
    description: 'test rule',
    thresholdMilligramsOrKcal: threshold,
    freeFromAllergenType: freeFromAllergenType,
    isActive: true,
    createdAt: DateTime(2026, 1, 1),
    createdByStaffId: 'manager-1',
  );
}

NutritionCalculationResult _nutritionResult({
  required RecipeCalculationStatus status,
  NutritionValueSet perPortion = const NutritionValueSet(),
}) {
  return NutritionCalculationResult(
    id: 'result-1',
    recipeId: 'recipe-1',
    recipeVersionId: 'version-1',
    totalValues: perPortion,
    perPortionValues: perPortion,
    portionCount: 1,
    missingIngredientIds: const [],
    status: status,
    confidence: NutritionConfidence.medium,
    calculationRevision: 1,
    calculatedAt: DateTime(2026, 1, 1),
  );
}

IngredientAllergenDeclaration _freeFromDeclaration({
  required String ingredientId,
  required AllergenType allergenType,
  bool confirmed = true,
}) {
  return IngredientAllergenDeclaration(
    id: '$ingredientId-$allergenType',
    organizationId: 'org-1',
    ingredientId: ingredientId,
    allergenType: allergenType,
    status: AllergenDeclarationStatus.explicitlyFreeFrom,
    sourceType: AllergenSourceType.manual,
    confidence: AllergenConfidence.high,
    isConfirmedByHuman: confirmed,
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

void main() {
  group('MenuLabelRuleEvaluator', () {
    test(
        'highProtein qualifies when the calculated value meets the '
        'threshold', () {
      final result = const MenuLabelRuleEvaluator().evaluate(
        rule: _rule(labelType: MenuLabelType.highProtein, threshold: 25000),
        nutritionResult: _nutritionResult(
          status: RecipeCalculationStatus.calculated,
          perPortion: const NutritionValueSet(proteinMilligrams: 30000),
        ),
        ingredientIds: const [],
        allergenDeclarationsByIngredientId: const {},
      );

      expect(result.qualifies, isTrue);
    });

    test('highProtein never qualifies from an incomplete nutrition result', () {
      final result = const MenuLabelRuleEvaluator().evaluate(
        rule: _rule(labelType: MenuLabelType.highProtein, threshold: 25000),
        nutritionResult: _nutritionResult(
          status: RecipeCalculationStatus.incomplete,
          perPortion: const NutritionValueSet(proteinMilligrams: 99000),
        ),
        ingredientIds: const [],
        allergenDeclarationsByIngredientId: const {},
      );

      expect(result.qualifies, isFalse);
    });

    test('lowCalorie qualifies when at or under the threshold', () {
      final result = const MenuLabelRuleEvaluator().evaluate(
        rule: _rule(labelType: MenuLabelType.lowCalorie, threshold: 400),
        nutritionResult: _nutritionResult(
          status: RecipeCalculationStatus.calculated,
          perPortion: const NutritionValueSet(energyKcal: 350),
        ),
        ingredientIds: const [],
        allergenDeclarationsByIngredientId: const {},
      );

      expect(result.qualifies, isTrue);
    });

    test(
        'glutenFree qualifies only when every ingredient has a confirmed '
        'explicitlyFreeFrom declaration', () {
      const evaluator = MenuLabelRuleEvaluator();
      final rule = _rule(
        labelType: MenuLabelType.glutenFree,
        freeFromAllergenType: AllergenType.gluten,
      );

      final allQualified = evaluator.evaluate(
        rule: rule,
        ingredientIds: const ['rice', 'chicken'],
        allergenDeclarationsByIngredientId: {
          'rice': [
            _freeFromDeclaration(
                ingredientId: 'rice', allergenType: AllergenType.gluten),
          ],
          'chicken': [
            _freeFromDeclaration(
                ingredientId: 'chicken', allergenType: AllergenType.gluten),
          ],
        },
      );
      expect(allQualified.qualifies, isTrue);

      final oneMissing = evaluator.evaluate(
        rule: rule,
        ingredientIds: const ['rice', 'bread'],
        allergenDeclarationsByIngredientId: {
          'rice': [
            _freeFromDeclaration(
                ingredientId: 'rice', allergenType: AllergenType.gluten),
          ],
        },
      );
      expect(oneMissing.qualifies, isFalse);

      final oneUnconfirmed = evaluator.evaluate(
        rule: rule,
        ingredientIds: const ['rice'],
        allergenDeclarationsByIngredientId: {
          'rice': [
            _freeFromDeclaration(
              ingredientId: 'rice',
              allergenType: AllergenType.gluten,
              confirmed: false,
            ),
          ],
        },
      );
      expect(oneUnconfirmed.qualifies, isFalse);
    });

    test('vegan has no automatic evaluator and never qualifies', () {
      final result = const MenuLabelRuleEvaluator().evaluate(
        rule: _rule(labelType: MenuLabelType.vegan),
        ingredientIds: const [],
        allergenDeclarationsByIngredientId: const {},
      );

      expect(result.qualifies, isFalse);
    });
  });
}
