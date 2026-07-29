import '../domain/compensation/courier_shift_schedule.dart';

/// Append-only storage for [CourierShiftSchedule], keyed by [shiftId] — a
/// manager rescheduling before the shift starts creates a new revision
/// (the latest one wins); no update/delete method exists.
abstract interface class CourierShiftScheduleRepository {
  Future<void> append(CourierShiftSchedule schedule);

  /// The latest [CourierShiftSchedule] for [shiftId], or `null` if a
  /// manager never scheduled one (earnings calculation then falls back to
  /// the shift's own actual `startedAt`/`endedAt`).
  Future<CourierShiftSchedule?> findLatestByShiftId(String shiftId);
}

class InMemoryCourierShiftScheduleRepository
    implements CourierShiftScheduleRepository {
  final Map<String, List<CourierShiftSchedule>> _byShiftId = {};

  @override
  Future<void> append(CourierShiftSchedule schedule) async {
    _byShiftId.putIfAbsent(schedule.shiftId, () => []).add(schedule);
  }

  @override
  Future<CourierShiftSchedule?> findLatestByShiftId(String shiftId) async {
    final history = _byShiftId[shiftId];
    if (history == null || history.isEmpty) return null;
    return history.last;
  }
}
