enum StockCountStatus { inProgress, submitted, approved, rejected }

/// One physical stock count session at a [StockLocation] — Phase 7
/// (`docs/decisions.md` ADR-024). "Recounts create new records" — a
/// `StockCount` is never reopened/edited once [StockCountStatus
/// .submitted]; a mistaken count is corrected by starting a new
/// `StockCount`, keeping every prior one intact.
class StockCount {
  const StockCount({
    required this.id,
    required this.branchId,
    required this.locationId,
    this.status = StockCountStatus.inProgress,
    required this.startedByStaffId,
    required this.startedAt,
    this.submittedAt,
    this.approvedByStaffId,
    this.approvedAt,
    this.rejectionReason,
  });

  final String id;
  final String branchId;
  final String locationId;
  final StockCountStatus status;
  final String startedByStaffId;
  final DateTime startedAt;
  final DateTime? submittedAt;
  final String? approvedByStaffId;
  final DateTime? approvedAt;
  final String? rejectionReason;

  StockCount copyWith({
    required StockCountStatus status,
    DateTime? submittedAt,
    String? approvedByStaffId,
    DateTime? approvedAt,
    String? rejectionReason,
  }) {
    return StockCount(
      id: id,
      branchId: branchId,
      locationId: locationId,
      status: status,
      startedByStaffId: startedByStaffId,
      startedAt: startedAt,
      submittedAt: submittedAt ?? this.submittedAt,
      approvedByStaffId: approvedByStaffId ?? this.approvedByStaffId,
      approvedAt: approvedAt ?? this.approvedAt,
      rejectionReason: rejectionReason ?? this.rejectionReason,
    );
  }
}
