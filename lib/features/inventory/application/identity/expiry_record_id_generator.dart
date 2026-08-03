abstract interface class ExpiryRecordIdGenerator {
  String nextExpiryRecordId();
}

class SequentialExpiryRecordIdGenerator implements ExpiryRecordIdGenerator {
  SequentialExpiryRecordIdGenerator({this.prefix = 'expiry-record'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextExpiryRecordId() => '$prefix-${++_sequence}';
}
