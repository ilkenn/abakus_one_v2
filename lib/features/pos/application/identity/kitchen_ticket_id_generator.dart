/// Generates a stable id for a new [KitchenTicket].
///
/// See `PaymentSplitIdGenerator`'s doc comment (Sprint 3C) for why this is
/// its own small, single-purpose contract.
abstract interface class KitchenTicketIdGenerator {
  String nextTicketId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialKitchenTicketIdGenerator implements KitchenTicketIdGenerator {
  SequentialKitchenTicketIdGenerator({this.prefix = 'ticket'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextTicketId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
