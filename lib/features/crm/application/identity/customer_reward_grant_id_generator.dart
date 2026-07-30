abstract interface class CustomerRewardGrantIdGenerator {
  String nextGrantId();
}

class SequentialCustomerRewardGrantIdGenerator
    implements CustomerRewardGrantIdGenerator {
  SequentialCustomerRewardGrantIdGenerator({this.prefix = 'reward-grant'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextGrantId() => '$prefix-${++_sequence}';
}
