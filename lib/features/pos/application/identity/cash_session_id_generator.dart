/// Generates a stable id for a new [CashSession].
abstract interface class CashSessionIdGenerator {
  String nextSessionId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialCashSessionIdGenerator implements CashSessionIdGenerator {
  SequentialCashSessionIdGenerator({this.prefix = 'cashsession'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextSessionId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
