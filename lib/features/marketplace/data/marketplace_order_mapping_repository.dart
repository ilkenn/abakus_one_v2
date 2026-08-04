import '../domain/marketplace_order_mapping.dart';

abstract interface class MarketplaceOrderMappingRepository {
  Future<void> save(MarketplaceOrderMapping mapping);
  Future<MarketplaceOrderMapping?> findByExternalOrderId(
      String externalOrderId);
}

class InMemoryMarketplaceOrderMappingRepository
    implements MarketplaceOrderMappingRepository {
  final Map<String, MarketplaceOrderMapping> _byExternalOrderId = {};

  @override
  Future<void> save(MarketplaceOrderMapping mapping) async =>
      _byExternalOrderId[mapping.externalOrderId] = mapping;

  @override
  Future<MarketplaceOrderMapping?> findByExternalOrderId(
      String externalOrderId) async {
    return _byExternalOrderId[externalOrderId];
  }
}
