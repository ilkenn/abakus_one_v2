abstract interface class SameDestinationGroupIdGenerator {
  String nextGroupId();
}

class SequentialSameDestinationGroupIdGenerator
    implements SameDestinationGroupIdGenerator {
  SequentialSameDestinationGroupIdGenerator({this.prefix = 'samedest'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextGroupId() => '$prefix-${++_sequence}';
}
