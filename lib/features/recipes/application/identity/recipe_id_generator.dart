abstract interface class RecipeIdGenerator {
  String nextRecipeId();
}

class SequentialRecipeIdGenerator implements RecipeIdGenerator {
  SequentialRecipeIdGenerator({this.prefix = 'recipe'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextRecipeId() => '$prefix-${++_sequence}';
}
