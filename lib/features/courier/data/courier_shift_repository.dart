import '../domain/shift/courier_shift.dart';
import '../domain/shift/courier_shift_status.dart';

/// Append-only storage for [CourierShift] revisions, keyed by
/// [CourierShift.id] — mirrors `CashSessionRepository`.
abstract interface class CourierShiftRepository {
  Future<void> save(CourierShift shift);
  Future<CourierShift?> findById(String shiftId);

  /// The active (non-terminal) shift for [courierId], or `null` — what
  /// `RequestCourierShift` checks before allowing a new one (only one
  /// active shift per courier).
  Future<CourierShift?> findActiveByCourierId(String courierId);

  Future<List<CourierShift>> findByCourierId(String courierId);

  /// Every shift currently `awaitingManagerApproval` for [branchId] — the
  /// manager approval queue.
  Future<List<CourierShift>> findPendingApprovalByBranchId(String branchId);
}

class InMemoryCourierShiftRepository implements CourierShiftRepository {
  final Map<String, List<CourierShift>> _historyById = {};

  @override
  Future<void> save(CourierShift shift) async {
    _historyById.putIfAbsent(shift.id, () => []).add(shift);
  }

  @override
  Future<CourierShift?> findById(String shiftId) async {
    final history = _historyById[shiftId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }

  @override
  Future<CourierShift?> findActiveByCourierId(String courierId) async {
    for (final history in _historyById.values) {
      if (history.isEmpty) continue;
      final latest = history.last;
      if (latest.courierId == courierId &&
          !CourierShiftStatusTransitions.isTerminal(latest.status)) {
        return latest;
      }
    }
    return null;
  }

  @override
  Future<List<CourierShift>> findByCourierId(String courierId) async {
    final result = <CourierShift>[];
    for (final history in _historyById.values) {
      if (history.isNotEmpty && history.last.courierId == courierId) {
        result.add(history.last);
      }
    }
    result.sort((a, b) => a.requestedAt.compareTo(b.requestedAt));
    return List.unmodifiable(result);
  }

  @override
  Future<List<CourierShift>> findPendingApprovalByBranchId(
      String branchId) async {
    final result = <CourierShift>[];
    for (final history in _historyById.values) {
      if (history.isEmpty) continue;
      final latest = history.last;
      if (latest.branchId == branchId &&
          latest.status == CourierShiftStatus.awaitingManagerApproval) {
        result.add(latest);
      }
    }
    return List.unmodifiable(result);
  }
}
