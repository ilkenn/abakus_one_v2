import 'cash_variance.dart';

/// Manager-review status of a [CashReconciliation].
enum CashReconciliationStatus { pendingApproval, approved, rejected }

/// The manager-approval record for one [CashCount] — separate from
/// `CashCount` itself (which only records *what was counted*), since a
/// single count may be reviewed, rejected, recounted, and reviewed again;
/// the count and its review are different events with different actors.
///
/// **Append-only**: a rejected [CashReconciliation] is never deleted or
/// edited — it remains in history exactly as decided
/// (`docs/business_rules.md`: rejected counts remain in history).
class CashReconciliation {
  const CashReconciliation({
    required this.id,
    required this.sessionId,
    required this.cashCountId,
    required this.status,
    required this.reviewedByStaffId,
    required this.reviewedAt,
    this.managerComments = '',
    this.varianceAccepted = false,
    this.variance,
  });

  final String id;
  final String sessionId;

  /// The specific [CashCount] this reconciliation reviews.
  final String cashCountId;

  final CashReconciliationStatus status;
  final String reviewedByStaffId;
  final DateTime reviewedAt;
  final String managerComments;

  /// Whether the manager explicitly accepted a non-zero [CashVariance]
  /// rather than treating it as grounds for rejection — a shortage/overage
  /// does not, by itself, force a rejection.
  final bool varianceAccepted;

  /// A copy of the reviewed [CashCount]'s [CashVariance], frozen here so a
  /// reconciliation's own record of "what variance was accepted/rejected"
  /// never depends on re-reading the (mutable-by-recount-history)
  /// `CashCount` list later.
  final CashVariance? variance;
}
