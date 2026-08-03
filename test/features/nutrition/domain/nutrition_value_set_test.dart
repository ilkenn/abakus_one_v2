import 'package:abakus_one_v2/features/nutrition/domain/nutrition_value_set.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('NutritionValueSet', () {
    test('isComplete is false when any field is missing', () {
      const values = NutritionValueSet(energyKcal: 165);
      expect(values.isComplete, isFalse);
    });

    test('isComplete is true only when every field is present', () {
      const values = NutritionValueSet(
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
      expect(values.isComplete, isTrue);
    });
  });
}
