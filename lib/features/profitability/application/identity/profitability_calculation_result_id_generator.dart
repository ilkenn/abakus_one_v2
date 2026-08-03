abstract interface class ProfitabilityCalculationResultIdGenerator {
  String nextProfitabilityCalculationResultId();
}

class SequentialProfitabilityCalculationResultIdGenerator
    implements ProfitabilityCalculationResultIdGenerator {
  SequentialProfitabilityCalculationResultIdGenerator({
    this.prefix = 'profitability-calculation-result',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextProfitabilityCalculationResultId() => '$prefix-${++_sequence}';
}
