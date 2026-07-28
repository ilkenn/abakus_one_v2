/// Generates a stable id for a new [RestaurantTable].
///
/// See `FloorPlanIdGenerator`'s doc comment for why this is its own small
/// contract rather than folded into `OrderIdentityProvider` or another
/// generator.
abstract interface class RestaurantTableIdGenerator {
  String nextTableId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialRestaurantTableIdGenerator
    implements RestaurantTableIdGenerator {
  SequentialRestaurantTableIdGenerator({this.prefix = 'table'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextTableId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
