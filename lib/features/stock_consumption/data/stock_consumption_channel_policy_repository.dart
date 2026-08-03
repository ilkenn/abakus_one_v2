import '../domain/stock_consumption_channel_policy.dart';

abstract interface class StockConsumptionChannelPolicyRepository {
  Future<void> save(StockConsumptionChannelPolicy policy);
  Future<StockConsumptionChannelPolicy?> findByBranchAndChannel(
      String branchId, String channelCode);
}

class InMemoryStockConsumptionChannelPolicyRepository
    implements StockConsumptionChannelPolicyRepository {
  final Map<String, StockConsumptionChannelPolicy> _byKey = {};

  String _key(String branchId, String channelCode) => '$branchId::$channelCode';

  @override
  Future<void> save(StockConsumptionChannelPolicy policy) async {
    _byKey[_key(policy.branchId, policy.channelCode)] = policy;
  }

  @override
  Future<StockConsumptionChannelPolicy?> findByBranchAndChannel(
      String branchId, String channelCode) async {
    return _byKey[_key(branchId, channelCode)];
  }
}
