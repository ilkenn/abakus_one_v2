/// The immutable record of closing an already-`approved` [CashSession] —
/// a value object embedded in [CashSession] (`null` until closed), mirrors
/// [CashOpening]'s own reasoning for not being a separate top-level
/// aggregate.
class CashClosing {
  const CashClosing({
    required this.closedByStaffId,
    required this.closedAt,
    required this.finalCashCountId,
    required this.reconciliationId,
  });

  final String closedByStaffId;
  final DateTime closedAt;

  /// The `CashCount` that was ultimately approved and closed against —
  /// the link a manager/auditor follows to see exactly what was counted.
  final String finalCashCountId;

  /// The `CashReconciliation` that approved [finalCashCountId].
  final String reconciliationId;
}
