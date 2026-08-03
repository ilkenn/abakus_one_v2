abstract interface class RecipeModifierImpactIdGenerator {
  String nextRecipeModifierImpactId();
}

class SequentialRecipeModifierImpactIdGenerator
    implements RecipeModifierImpactIdGenerator {
  SequentialRecipeModifierImpactIdGenerator({
    this.prefix = 'recipe-modifier-impact',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextRecipeModifierImpactId() => '$prefix-${++_sequence}';
}
