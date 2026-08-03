abstract interface class BowlBuilderIngredientRecipeMappingIdGenerator {
  String nextBowlBuilderIngredientRecipeMappingId();
}

class SequentialBowlBuilderIngredientRecipeMappingIdGenerator
    implements BowlBuilderIngredientRecipeMappingIdGenerator {
  SequentialBowlBuilderIngredientRecipeMappingIdGenerator({
    this.prefix = 'bowl-builder-mapping',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextBowlBuilderIngredientRecipeMappingId() => '$prefix-${++_sequence}';
}
