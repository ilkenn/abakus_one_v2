/// Generates a stable, session-local id for a new `PaymentSplit`.
///
/// Deliberately separate from `OrderIdentityProvider` and
/// `PosOrderLineDraftIdGenerator` for the same reason those two are kept
/// apart from each other: a split id is ephemeral, session-local
/// correlation data, not a business identity — its own small,
/// single-purpose contract (`docs/decisions.md` ADR-012).
abstract interface class PaymentSplitIdGenerator {
  String nextSplitId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialPaymentSplitIdGenerator implements PaymentSplitIdGenerator {
  SequentialPaymentSplitIdGenerator({this.prefix = 'split'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextSplitId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
