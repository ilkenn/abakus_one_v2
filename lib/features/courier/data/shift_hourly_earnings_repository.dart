import '../domain/compensation/shift_hourly_earnings.dart';

/// Append-only storage for [ShiftHourlyEarnings] — no update/delete
/// method; `CalculateShiftHourlyEarnings` is idempotent by checking
/// [findByShiftId] before computing a new one.
abstract interface class ShiftHourlyEarningsRepository {
  Future<void> append(ShiftHourlyEarnings earnings);
  Future<ShiftHourlyEarnings?> findById(String id);
  Future<ShiftHourlyEarnings?> findByShiftId(String shiftId);

  Future<List<ShiftHourlyEarnings>> findByCourierIdAndPeriod({
    required String courierId,
    required DateTime periodStart,
    required DateTime periodEnd,
  });
}

class InMemoryShiftHourlyEarningsRepository
    implements ShiftHourlyEarningsRepository {
  final List<ShiftHourlyEarnings> _all = [];

  @override
  Future<void> append(ShiftHourlyEarnings earnings) async {
    _all.add(earnings);
  }

  @override
  Future<ShiftHourlyEarnings?> findById(String id) async {
    for (final e in _all) {
      if (e.id == id) return e;
    }
    return null;
  }

  @override
  Future<ShiftHourlyEarnings?> findByShiftId(String shiftId) async {
    for (final e in _all) {
      if (e.shiftId == shiftId) return e;
    }
    return null;
  }

  @override
  Future<List<ShiftHourlyEarnings>> findByCourierIdAndPeriod({
    required String courierId,
    required DateTime periodStart,
    required DateTime periodEnd,
  }) async {
    return List.unmodifiable(_all.where((e) =>
        e.courierId == courierId &&
        !e.calculatedAt.isBefore(periodStart) &&
        e.calculatedAt.isBefore(periodEnd)));
  }
}
