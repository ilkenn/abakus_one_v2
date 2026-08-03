abstract interface class WasteRecordIdGenerator {
  String nextWasteRecordId();
}

class SequentialWasteRecordIdGenerator implements WasteRecordIdGenerator {
  SequentialWasteRecordIdGenerator({this.prefix = 'waste-record'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextWasteRecordId() => '$prefix-${++_sequence}';
}
