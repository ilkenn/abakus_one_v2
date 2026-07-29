import 'courier_settlement_status.dart';
import 'courier_settlement_variance.dart';

/// The manager-review decision record for one [CourierCashDeclaration] —
/// separate from the declaration itself (which only records *what the
/// courier declared*), since a single declaration may be reviewed,
/// rejected, redeclared, and reviewed again; the declaration and its
/// review are different events with different actors. Mirrors
/// `CashReconciliation`'s reasoning exactly.
///
/// **Append-only**: only ever created once a decision is made — a
/// rejected [CourierSettlement] is never deleted or edited, it remains in
/// history exactly as decided. Unlike `CashReconciliationStatus`, this
/// status has no `pendingApproval` value: a [CourierSettlement] record is
/// only ever constructed as the finished decision (by `ApproveCourierSettlement`/
/// `RejectCourierSettlement`); "pending" is represented by the *absence*
/// of one for the current declaration, via
/// `CourierSettlementSessionStatus.pendingApproval` on the session itself.
class CourierSettlement {
  const CourierSettlement({
    required this.id,
    required this.settlementSessionId,
    required this.declarationId,
    required this.status,
    required this.reviewedByStaffId,
    required this.reviewedAt,
    this.managerNotes = '',
    this.varianceAccepted = false,
    this.variance,
  });

  final String id;
  final String settlementSessionId;

  /// The specific [CourierCashDeclaration] this settlement reviews.
  final String declarationId;

  final CourierSettlementStatus status;
  final String reviewedByStaffId;
  final DateTime reviewedAt;
  final String managerNotes;

  /// Whether the manager explicitly accepted a non-zero
  /// [CourierSettlementVariance] rather than treating it as grounds for
  /// rejection — a shortage/overage does not, by itself, force a
  /// rejection.
  final bool varianceAccepted;

  /// A copy of the reviewed [CourierCashDeclaration]'s
  /// [CourierSettlementVariance], frozen here so this record's own
  /// account of "what variance was accepted/rejected" never depends on
  /// re-reading the (mutable-by-redeclaration-history) declaration list
  /// later.
  final CourierSettlementVariance? variance;
}
