abstract interface class StockConsumptionChannelPolicyIdGenerator {
  String nextStockConsumptionChannelPolicyId();
}

class SequentialStockConsumptionChannelPolicyIdGenerator
    implements StockConsumptionChannelPolicyIdGenerator {
  SequentialStockConsumptionChannelPolicyIdGenerator({
    this.prefix = 'stock-consumption-channel-policy',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextStockConsumptionChannelPolicyId() => '$prefix-${++_sequence}';
}
