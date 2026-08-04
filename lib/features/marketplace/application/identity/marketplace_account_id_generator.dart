abstract interface class MarketplaceAccountIdGenerator {
  String nextMarketplaceAccountId();
}

class SequentialMarketplaceAccountIdGenerator
    implements MarketplaceAccountIdGenerator {
  SequentialMarketplaceAccountIdGenerator({this.prefix = 'mkt-account'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextMarketplaceAccountId() => '$prefix-${++_sequence}';
}
