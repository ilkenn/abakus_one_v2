abstract interface class NutritionCalculationResultIdGenerator {
  String nextNutritionCalculationResultId();
}

class SequentialNutritionCalculationResultIdGenerator
    implements NutritionCalculationResultIdGenerator {
  SequentialNutritionCalculationResultIdGenerator({
    this.prefix = 'nutrition-calculation-result',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextNutritionCalculationResultId() => '$prefix-${++_sequence}';
}
