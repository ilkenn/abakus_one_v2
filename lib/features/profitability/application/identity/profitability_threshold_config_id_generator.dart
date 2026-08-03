abstract interface class ProfitabilityThresholdConfigIdGenerator {
  String nextProfitabilityThresholdConfigId();
}

class SequentialProfitabilityThresholdConfigIdGenerator
    implements ProfitabilityThresholdConfigIdGenerator {
  SequentialProfitabilityThresholdConfigIdGenerator({
    this.prefix = 'profitability-threshold-config',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextProfitabilityThresholdConfigId() => '$prefix-${++_sequence}';
}
