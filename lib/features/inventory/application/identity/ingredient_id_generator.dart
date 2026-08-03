abstract interface class IngredientIdGenerator {
  String nextIngredientId();
}

class SequentialIngredientIdGenerator implements IngredientIdGenerator {
  SequentialIngredientIdGenerator({this.prefix = 'ingredient'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextIngredientId() => '$prefix-${++_sequence}';
}
