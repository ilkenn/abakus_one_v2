/// Generates a stable id for a new [CashReconciliation].
abstract interface class CashReconciliationIdGenerator {
  String nextReconciliationId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialCashReconciliationIdGenerator
    implements CashReconciliationIdGenerator {
  SequentialCashReconciliationIdGenerator({this.prefix = 'reconciliation'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextReconciliationId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
