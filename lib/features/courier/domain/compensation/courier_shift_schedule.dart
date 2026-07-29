/// A manager-set planned start/end time for a [CourierShift] — the
/// "ScheduledShiftStart"/scheduled-end the compensation business rules
/// reference. **Deliberately not a field on `CourierShift` itself** —
/// `CourierShift` (Phase 5) has no scheduled-time concept at all (only
/// `requestedAt`/`approvedAt`/`startedAt`/`endedAt`, all *actual*
/// timestamps), and this sprint must not modify Phase 5's existing
/// domain types. A companion, append-only, `shiftId`-keyed record is the
/// additive alternative — see `docs/decisions.md` ADR-018.
///
/// When no [CourierShiftSchedule] exists for a shift, earnings
/// calculation falls back to the shift's own actual `startedAt`/`endedAt`
/// as both the "scheduled" and "actual" instants — meaning no early/late
/// arrival adjustment is possible without a manager having explicitly set
/// one. A conservative, explicit default, not a fabricated number.
class CourierShiftSchedule {
  const CourierShiftSchedule({
    required this.id,
    required this.shiftId,
    required this.courierId,
    required this.scheduledStart,
    required this.scheduledEnd,
    required this.setByStaffId,
    required this.setAt,
  });

  final String id;
  final String shiftId;
  final String courierId;
  final DateTime scheduledStart;
  final DateTime scheduledEnd;
  final String setByStaffId;
  final DateTime setAt;
}
