/// A manager-approved manual correction applied to a [CashSession] —
/// links to (never duplicates) the [CashMovement]
/// (`CashMovementType.correction`) that actually carries the signed
/// amount, so the financial effect is recorded exactly once.
///
/// **Append-only**, like every other cash record in this sprint — a
/// correction is never itself corrected in place; a further adjustment is
/// simply another [CashAdjustment]/[CashMovement] pair.
class CashAdjustment {
  const CashAdjustment({
    required this.id,
    required this.sessionId,
    required this.movementId,
    required this.reason,
    required this.requestedByStaffId,
    required this.approvedByStaffId,
    required this.createdAt,
  });

  final String id;
  final String sessionId;

  /// The `CashMovementType.correction` movement this adjustment produced.
  final String movementId;

  final String reason;
  final String requestedByStaffId;

  /// Never equal to [requestedByStaffId] — enforced by
  /// `RecordCashAdjustment` (a requester cannot approve their own
  /// adjustment, the same self-approval rule `CashReconciliation` enforces
  /// for counts).
  final String approvedByStaffId;

  final DateTime createdAt;
}
