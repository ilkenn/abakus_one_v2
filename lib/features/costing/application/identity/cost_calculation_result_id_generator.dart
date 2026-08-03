abstract interface class CostCalculationResultIdGenerator {
  String nextCostCalculationResultId();
}

class SequentialCostCalculationResultIdGenerator
    implements CostCalculationResultIdGenerator {
  SequentialCostCalculationResultIdGenerator({
    this.prefix = 'cost-calculation-result',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextCostCalculationResultId() => '$prefix-${++_sequence}';
}
