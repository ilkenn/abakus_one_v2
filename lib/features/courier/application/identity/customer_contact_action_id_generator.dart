abstract interface class CustomerContactActionIdGenerator {
  String nextActionId();
}

class SequentialCustomerContactActionIdGenerator
    implements CustomerContactActionIdGenerator {
  SequentialCustomerContactActionIdGenerator({this.prefix = 'ccontact'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextActionId() => '$prefix-${++_sequence}';
}
