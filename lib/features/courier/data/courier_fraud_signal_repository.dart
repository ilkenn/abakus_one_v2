import '../domain/fraud/courier_fraud_signal.dart';

/// Append-only storage for [CourierFraudSignal] — Sprint 5B Part 8.
abstract interface class CourierFraudSignalRepository {
  Future<void> append(CourierFraudSignal signal);
  Future<List<CourierFraudSignal>> findByCourierId(String courierId);
}

class InMemoryCourierFraudSignalRepository
    implements CourierFraudSignalRepository {
  final List<CourierFraudSignal> _signals = [];

  @override
  Future<void> append(CourierFraudSignal signal) async {
    _signals.add(signal);
  }

  @override
  Future<List<CourierFraudSignal>> findByCourierId(String courierId) async {
    return List.unmodifiable(
      _signals.where((s) => s.courierId == courierId),
    );
  }
}
