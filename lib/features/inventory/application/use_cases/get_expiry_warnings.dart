import '../../data/stock_lot_repository.dart';
import '../../domain/stock_lot.dart';

/// Lists every [StockLot] at a location expiring within
/// [withinDuration] of [asOf] — Phase 7 (`docs/decisions.md`
/// ADR-024). Read-only; never mutates anything, so it's not
/// authorization-gated beyond whatever screen-level access already
/// governs viewing inventory (the same "read is implicit for anyone
/// who can already see this screen" precedent every other Phase 7
/// read-only query use case follows).
class GetExpiryWarnings {
  const GetExpiryWarnings({required StockLotRepository repository})
      : _repository = repository;

  final StockLotRepository _repository;

  Future<List<StockLot>> call({
    required String locationId,
    required DateTime asOf,
    required Duration withinDuration,
  }) async {
    final lotsWithExpiry =
        await _repository.findExpiringByLocationId(locationId);
    final threshold = asOf.add(withinDuration);
    return lotsWithExpiry
        .where((lot) =>
            lot.expiresAt != null && !lot.expiresAt!.isAfter(threshold))
        .toList(growable: false);
  }
}
