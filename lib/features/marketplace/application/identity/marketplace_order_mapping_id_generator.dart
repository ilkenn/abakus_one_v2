abstract interface class MarketplaceOrderMappingIdGenerator {
  String nextMarketplaceOrderMappingId();
}

class SequentialMarketplaceOrderMappingIdGenerator
    implements MarketplaceOrderMappingIdGenerator {
  SequentialMarketplaceOrderMappingIdGenerator({this.prefix = 'mkt-order-map'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextMarketplaceOrderMappingId() => '$prefix-${++_sequence}';
}
