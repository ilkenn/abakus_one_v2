/// A manager-approved manual correction applied to a
/// [CourierSettlementSession] — links to (never duplicates) the
/// [CashMovement] (`CashMovementType.correction`) that actually carries
/// the signed amount, so the financial effect is recorded exactly once.
/// Mirrors `CashAdjustment`'s shape and reasoning exactly.
///
/// **Append-only** — a correction is never itself corrected in place; a
/// further adjustment is simply another [CourierSettlementAdjustment]/
/// `CashMovement` pair.
class CourierSettlementAdjustment {
  const CourierSettlementAdjustment({
    required this.id,
    required this.settlementSessionId,
    required this.movementId,
    required this.reason,
    required this.requestedByStaffId,
    required this.approvedByStaffId,
    required this.createdAt,
  });

  final String id;
  final String settlementSessionId;

  /// The `CashMovementType.correction` movement this adjustment produced.
  final String movementId;

  final String reason;
  final String requestedByStaffId;

  /// Never equal to [requestedByStaffId] — enforced by
  /// `RecordCourierSettlementAdjustment` (a requester cannot approve their
  /// own adjustment, the same self-approval rule `CourierSettlement`
  /// enforces for declarations).
  final String approvedByStaffId;

  final DateTime createdAt;
}
