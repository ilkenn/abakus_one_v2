abstract interface class MarketplaceStoreIdGenerator {
  String nextMarketplaceStoreId();
}

class SequentialMarketplaceStoreIdGenerator
    implements MarketplaceStoreIdGenerator {
  SequentialMarketplaceStoreIdGenerator({this.prefix = 'mkt-store'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextMarketplaceStoreId() => '$prefix-${++_sequence}';
}
