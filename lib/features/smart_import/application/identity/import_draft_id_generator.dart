abstract interface class ImportDraftIdGenerator {
  String nextImportDraftId();
}

class SequentialImportDraftIdGenerator implements ImportDraftIdGenerator {
  SequentialImportDraftIdGenerator({this.prefix = 'import-draft'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextImportDraftId() => '$prefix-${++_sequence}';
}
