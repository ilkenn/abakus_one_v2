import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/inventory/domain/quantity.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_aggregator.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_confidence.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_data_source_type.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_reference_entry.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_value_set.dart';
import 'package:abakus_one_v2/features/recipes/domain/flattened_ingredient_line.dart';
import 'package:flutter_test/flutter_test.dart';

NutritionReferenceEntry _entry({
  required String ingredientId,
  required NutritionValueSet values,
  InventoryUnit referenceUnit = InventoryUnit.gram,
  NutritionConfidence confidence = NutritionConfidence.medium,
}) {
  return NutritionReferenceEntry(
    id: '$ingredientId-entry',
    organizationId: 'org-1',
    ingredientId: ingredientId,
    values: values,
    referenceUnit: referenceUnit,
    sourceType: NutritionDataSourceType.externalProvider,
    confidence: confidence,
    isManuallyOverridden: false,
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

const _completeChicken = NutritionValueSet(
  energyKcal: 165,
  proteinMilligrams: 31000,
  carbohydrateMilligrams: 0,
  fatMilligrams: 3600,
  saturatedFatMilligrams: 1000,
  fiberMilligrams: 0,
  sugarMilligrams: 0,
  saltMilligrams: 74,
  sodiumMilligrams: 74,
);

void main() {
  group('NutritionAggregator', () {
    test('scales a single ingredient by its quantity', () {
      final outcome = const NutritionAggregator().aggregate(
        lines: [
          FlattenedIngredientLine(
            'chicken',
            Quantity.fromWhole(200, InventoryUnit.gram),
          ),
        ],
        referenceEntriesByIngredientId: {
          'chicken': _entry(ingredientId: 'chicken', values: _completeChicken),
        },
      );

      expect(outcome.missingIngredientIds, isEmpty);
      // 200g is 2x the 100g reference -> exactly double every field.
      expect(outcome.totalValues.energyKcal, 330);
      expect(outcome.totalValues.proteinMilligrams, 62000);
      expect(outcome.confidence, NutritionConfidence.medium);
    });

    test(
        'an ingredient with no reference entry is reported missing, '
        'never silently zeroed', () {
      final outcome = const NutritionAggregator().aggregate(
        lines: [
          FlattenedIngredientLine(
            'mystery',
            Quantity.fromWhole(50, InventoryUnit.gram),
          ),
        ],
        referenceEntriesByIngredientId: const {},
      );

      expect(outcome.missingIngredientIds, ['mystery']);
      expect(outcome.totalValues.energyKcal, isNull);
    });

    test('an incomplete reference entry is treated as missing entirely', () {
      final outcome = const NutritionAggregator().aggregate(
        lines: [
          FlattenedIngredientLine(
            'partial',
            Quantity.fromWhole(100, InventoryUnit.gram),
          ),
        ],
        referenceEntriesByIngredientId: {
          'partial': _entry(
            ingredientId: 'partial',
            values: const NutritionValueSet(energyKcal: 100),
          ),
        },
      );

      expect(outcome.missingIngredientIds, ['partial']);
    });

    test(
        'a unit mismatch between the line and the reference entry is '
        'treated as missing', () {
      final outcome = const NutritionAggregator().aggregate(
        lines: [
          FlattenedIngredientLine(
            'sauce',
            Quantity.fromWhole(50, InventoryUnit.milliliter),
          ),
        ],
        referenceEntriesByIngredientId: {
          'sauce': _entry(
            ingredientId: 'sauce',
            values: _completeChicken,
            referenceUnit: InventoryUnit.gram,
          ),
        },
      );

      expect(outcome.missingIngredientIds, ['sauce']);
    });

    test('overall confidence is the lowest among contributing ingredients', () {
      final outcome = const NutritionAggregator().aggregate(
        lines: [
          FlattenedIngredientLine(
              'a', Quantity.fromWhole(100, InventoryUnit.gram)),
          FlattenedIngredientLine(
              'b', Quantity.fromWhole(100, InventoryUnit.gram)),
        ],
        referenceEntriesByIngredientId: {
          'a': _entry(
            ingredientId: 'a',
            values: _completeChicken,
            confidence: NutritionConfidence.high,
          ),
          'b': _entry(
            ingredientId: 'b',
            values: _completeChicken,
            confidence: NutritionConfidence.low,
          ),
        },
      );

      expect(outcome.confidence, NutritionConfidence.low);
    });

    test('no contributing ingredient at all yields unknown confidence', () {
      final outcome = const NutritionAggregator().aggregate(
        lines: [
          FlattenedIngredientLine(
              'missing', Quantity.fromWhole(10, InventoryUnit.gram)),
        ],
        referenceEntriesByIngredientId: const {},
      );

      expect(outcome.confidence, NutritionConfidence.unknown);
    });
  });
}
