/// Generates a stable id for a new [GuestSession]. See
/// `TableSessionIdGenerator`'s doc comment for why this is its own small,
/// single-purpose contract.
abstract interface class GuestSessionIdGenerator {
  String nextGuestSessionId();
}

/// The only implementation today — a simple, in-memory monotonic counter,
/// collision-safe only within one running instance.
class SequentialGuestSessionIdGenerator implements GuestSessionIdGenerator {
  SequentialGuestSessionIdGenerator({this.prefix = 'gsession'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextGuestSessionId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
