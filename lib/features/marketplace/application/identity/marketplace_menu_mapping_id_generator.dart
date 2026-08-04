abstract interface class MarketplaceMenuMappingIdGenerator {
  String nextMarketplaceMenuMappingId();
}

class SequentialMarketplaceMenuMappingIdGenerator
    implements MarketplaceMenuMappingIdGenerator {
  SequentialMarketplaceMenuMappingIdGenerator({this.prefix = 'mkt-menu-map'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextMarketplaceMenuMappingId() => '$prefix-${++_sequence}';
}
