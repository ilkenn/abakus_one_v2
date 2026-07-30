import '../../data/courier_operational_audit_entry_repository.dart';
import '../../data/courier_repository.dart';
import '../../domain/audit/courier_operation_timeline_entry.dart';

/// Assembles the manager-facing "Operation Timeline" for a branch —
/// Sprint 5C Part 11. **Not a new log**: every entry is sourced from the
/// already-comprehensive, already-timestamped
/// `CourierOperationalAuditEntryRepository` (every manager/system action
/// across Sprint 5A/5B/5C is already recorded there) — this only sorts
/// chronologically and resolves each entry's courier name for display.
class BuildCourierOperationTimeline {
  const BuildCourierOperationTimeline({
    required CourierOperationalAuditEntryRepository auditRepository,
    required CourierRepository courierRepository,
  })  : _auditRepository = auditRepository,
        _courierRepository = courierRepository;

  final CourierOperationalAuditEntryRepository _auditRepository;
  final CourierRepository _courierRepository;

  /// Most-recent-first, matching `CourierCommunicationCenterScreen`'s own
  /// history ordering convention.
  Future<List<CourierOperationTimelineEntry>> call({
    required String branchId,
  }) async {
    final entries = await _auditRepository.findByBranchId(branchId);
    final sorted = [...entries]
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final courierIds = {
      for (final e in sorted)
        if (e.courierId != null) e.courierId!,
    };
    final displayNames = <String, String>{};
    for (final courierId in courierIds) {
      final courier = await _courierRepository.findById(courierId);
      if (courier != null) displayNames[courierId] = courier.displayName;
    }

    return [
      for (final e in sorted)
        CourierOperationTimelineEntry(
          timestamp: e.timestamp,
          type: e.type,
          description: e.description,
          actorStaffId: e.actorStaffId,
          courierId: e.courierId,
          courierDisplayName:
              e.courierId == null ? null : displayNames[e.courierId],
        ),
    ];
  }
}
