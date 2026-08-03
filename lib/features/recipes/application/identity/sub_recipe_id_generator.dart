abstract interface class SubRecipeIdGenerator {
  String nextSubRecipeId();
}

class SequentialSubRecipeIdGenerator implements SubRecipeIdGenerator {
  SequentialSubRecipeIdGenerator({this.prefix = 'sub-recipe'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextSubRecipeId() => '$prefix-${++_sequence}';
}
