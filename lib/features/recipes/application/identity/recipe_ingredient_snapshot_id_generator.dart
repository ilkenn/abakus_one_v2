abstract interface class RecipeIngredientSnapshotIdGenerator {
  String nextRecipeIngredientSnapshotId();
}

class SequentialRecipeIngredientSnapshotIdGenerator
    implements RecipeIngredientSnapshotIdGenerator {
  SequentialRecipeIngredientSnapshotIdGenerator({
    this.prefix = 'recipe-ingredient-snapshot',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextRecipeIngredientSnapshotId() => '$prefix-${++_sequence}';
}
