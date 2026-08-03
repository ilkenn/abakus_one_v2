abstract interface class NutritionReferenceEntryIdGenerator {
  String nextNutritionReferenceEntryId();
}

class SequentialNutritionReferenceEntryIdGenerator
    implements NutritionReferenceEntryIdGenerator {
  SequentialNutritionReferenceEntryIdGenerator({
    this.prefix = 'nutrition-reference-entry',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextNutritionReferenceEntryId() => '$prefix-${++_sequence}';
}
