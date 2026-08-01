abstract interface class TranslationEntryIdGenerator {
  String nextTranslationEntryId();
}

class SequentialTranslationEntryIdGenerator
    implements TranslationEntryIdGenerator {
  SequentialTranslationEntryIdGenerator({this.prefix = 'translation'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextTranslationEntryId() => '$prefix-${++_sequence}';
}
