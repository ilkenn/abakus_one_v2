import '../domain/delivery/courier_delivery_sequence.dart';

/// Append-only storage for [CourierDeliverySequence] — Sprint 5C.
abstract interface class CourierDeliverySequenceRepository {
  Future<void> save(CourierDeliverySequence sequence);
  Future<CourierDeliverySequence?> findLatestByCourierId(String courierId);
}

class InMemoryCourierDeliverySequenceRepository
    implements CourierDeliverySequenceRepository {
  final Map<String, List<CourierDeliverySequence>> _byCourierId = {};

  @override
  Future<void> save(CourierDeliverySequence sequence) async {
    _byCourierId.putIfAbsent(sequence.courierId, () => []).add(sequence);
  }

  @override
  Future<CourierDeliverySequence?> findLatestByCourierId(
      String courierId) async {
    final history = _byCourierId[courierId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }
}
