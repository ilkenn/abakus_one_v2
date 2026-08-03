import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/recipes/domain/recipe_line.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RecipeLine', () {
    test('an ingredient-only line constructs successfully', () {
      final line = RecipeLine(
        id: 'line-1',
        ingredientId: 'ingredient-1',
        quantity: Quantity.fromWhole(100, InventoryUnit.gram),
      );

      expect(line.referencesIngredient, isTrue);
      expect(line.referencesSubRecipe, isFalse);
    });

    test('a sub-recipe-only line constructs successfully', () {
      final line = RecipeLine(
        id: 'line-1',
        subRecipeId: 'sub-recipe-1',
        quantity: Quantity.fromWhole(200, InventoryUnit.gram),
      );

      expect(line.referencesSubRecipe, isTrue);
      expect(line.referencesIngredient, isFalse);
    });

    test('neither ingredientId nor subRecipeId throws', () {
      expect(
        () => RecipeLine(
          id: 'line-1',
          quantity: Quantity.fromWhole(100, InventoryUnit.gram),
        ),
        throwsA(isA<InvalidRecipeLineViolation>()),
      );
    });

    test('both ingredientId and subRecipeId throws', () {
      expect(
        () => RecipeLine(
          id: 'line-1',
          ingredientId: 'ingredient-1',
          subRecipeId: 'sub-recipe-1',
          quantity: Quantity.fromWhole(100, InventoryUnit.gram),
        ),
        throwsA(isA<InvalidRecipeLineViolation>()),
      );
    });
  });
}
