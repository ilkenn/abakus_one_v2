abstract interface class RecipeIngredientLinkIdGenerator {
  String nextRecipeIngredientLinkId();
}

class SequentialRecipeIngredientLinkIdGenerator
    implements RecipeIngredientLinkIdGenerator {
  SequentialRecipeIngredientLinkIdGenerator({this.prefix = 'recipe-link'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextRecipeIngredientLinkId() => '$prefix-${++_sequence}';
}
