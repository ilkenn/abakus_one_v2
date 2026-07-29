/// Generates a stable id for a new `CourierCashDeclaration`.
abstract interface class CourierCashDeclarationIdGenerator {
  String nextDeclarationId();
}

/// The only implementation this sprint — a simple, in-memory monotonic
/// counter, collision-safe only within one running instance.
class SequentialCourierCashDeclarationIdGenerator
    implements CourierCashDeclarationIdGenerator {
  SequentialCourierCashDeclarationIdGenerator({this.prefix = 'cdeclaration'});

  final String prefix;
  int _sequence = 0;

  @override
  String nextDeclarationId() {
    _sequence += 1;
    return '$prefix-$_sequence';
  }
}
