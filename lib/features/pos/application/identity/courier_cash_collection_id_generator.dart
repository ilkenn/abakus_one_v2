/// Generates a stable id for a new `CourierCashCollection`.
abstract interface class CourierCashCollectionIdGenerator {
  String nextCollectionId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialCourierCashCollectionIdGenerator
    implements CourierCashCollectionIdGenerator {
  SequentialCourierCashCollectionIdGenerator({this.prefix = 'ccollection'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextCollectionId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
