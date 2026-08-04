abstract interface class MarketplaceBranchMappingIdGenerator {
  String nextMarketplaceBranchMappingId();
}

class SequentialMarketplaceBranchMappingIdGenerator
    implements MarketplaceBranchMappingIdGenerator {
  SequentialMarketplaceBranchMappingIdGenerator(
      {this.prefix = 'mkt-branch-map'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextMarketplaceBranchMappingId() => '$prefix-${++_sequence}';
}
