abstract interface class CustomerAdminNoteIdGenerator {
  String nextNoteId();
}

class SequentialCustomerAdminNoteIdGenerator
    implements CustomerAdminNoteIdGenerator {
  SequentialCustomerAdminNoteIdGenerator({this.prefix = 'customer-note'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextNoteId() => '$prefix-${++_sequence}';
}
