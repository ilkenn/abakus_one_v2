abstract interface class CustomerVisitIdGenerator {
  String nextVisitId();
}

class SequentialCustomerVisitIdGenerator implements CustomerVisitIdGenerator {
  SequentialCustomerVisitIdGenerator({this.prefix = 'visit'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextVisitId() => '$prefix-${++_sequence}';
}
