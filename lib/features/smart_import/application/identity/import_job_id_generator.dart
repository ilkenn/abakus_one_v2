abstract interface class ImportJobIdGenerator {
  String nextImportJobId();
}

class SequentialImportJobIdGenerator implements ImportJobIdGenerator {
  SequentialImportJobIdGenerator({this.prefix = 'import-job'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextImportJobId() => '$prefix-${++_sequence}';
}
