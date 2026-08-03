abstract interface class SubRecipeVersionIdGenerator {
  String nextSubRecipeVersionId();
}

class SequentialSubRecipeVersionIdGenerator
    implements SubRecipeVersionIdGenerator {
  SequentialSubRecipeVersionIdGenerator({this.prefix = 'sub-recipe-version'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextSubRecipeVersionId() => '$prefix-${++_sequence}';
}
