abstract interface class CustomerIdGenerator {
  String nextCustomerId();
}

class SequentialCustomerIdGenerator implements CustomerIdGenerator {
  SequentialCustomerIdGenerator({this.prefix = 'customer'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextCustomerId() => '$prefix-${++_sequence}';
}
