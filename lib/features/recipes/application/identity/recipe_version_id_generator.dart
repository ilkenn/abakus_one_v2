abstract interface class RecipeVersionIdGenerator {
  String nextRecipeVersionId();
}

class SequentialRecipeVersionIdGenerator implements RecipeVersionIdGenerator {
  SequentialRecipeVersionIdGenerator({this.prefix = 'recipe-version'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextRecipeVersionId() => '$prefix-${++_sequence}';
}
