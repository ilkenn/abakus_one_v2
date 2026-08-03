import '../domain/stock_reservation.dart';

abstract interface class StockReservationRepository {
  Future<void> save(StockReservation reservation);
  Future<StockReservation?> findById(String id);
  Future<List<StockReservation>> findByOrderId(String orderId);
}

class InMemoryStockReservationRepository implements StockReservationRepository {
  final Map<String, StockReservation> _byId = {};

  @override
  Future<void> save(StockReservation reservation) async =>
      _byId[reservation.id] = reservation;

  @override
  Future<StockReservation?> findById(String id) async => _byId[id];

  @override
  Future<List<StockReservation>> findByOrderId(String orderId) async {
    return List.unmodifiable(
      _byId.values.where((r) => r.relatedOrderId == orderId),
    );
  }
}
