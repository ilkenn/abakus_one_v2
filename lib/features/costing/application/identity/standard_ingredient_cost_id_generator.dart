abstract interface class StandardIngredientCostIdGenerator {
  String nextStandardIngredientCostId();
}

class SequentialStandardIngredientCostIdGenerator
    implements StandardIngredientCostIdGenerator {
  SequentialStandardIngredientCostIdGenerator({
    this.prefix = 'standard-ingredient-cost',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextStandardIngredientCostId() => '$prefix-${++_sequence}';
}
