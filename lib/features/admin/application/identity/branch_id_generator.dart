abstract interface class BranchIdGenerator {
  String nextBranchId();
}

class SequentialBranchIdGenerator implements BranchIdGenerator {
  SequentialBranchIdGenerator({this.prefix = 'branch'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextBranchId() => '$prefix-${++_sequence}';
}
