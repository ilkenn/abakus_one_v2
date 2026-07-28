import '../models/order_closure.dart';
import '../models/order_closure_lifecycle_status.dart';

/// A filter over [OrderClosure] records — the foundation a Closed Accounts
/// list screen filters/searches by ("filtreleme ve audit timeline"). Pure
/// domain logic: no Flutter/Riverpod import, no repository dependency —
/// [apply] filters whatever list of records it's given.
class ClosedOrderRecordFilter {
  const ClosedOrderRecordFilter({
    this.closedFrom,
    this.closedTo,
    this.closedByStaffId,
    this.lifecycleStatus,
  });

  /// Inclusive lower bound on [OrderClosure.closedAt].
  final DateTime? closedFrom;

  /// Inclusive upper bound on [OrderClosure.closedAt].
  final DateTime? closedTo;

  final String? closedByStaffId;
  final OrderClosureLifecycleStatus? lifecycleStatus;

  bool matches(OrderClosure closure) {
    final closedAt = closure.closedAt;
    if (closedFrom != null && (closedAt == null || closedAt.isBefore(closedFrom!))) {
      return false;
    }
    if (closedTo != null && (closedAt == null || closedAt.isAfter(closedTo!))) {
      return false;
    }
    if (closedByStaffId != null && closure.closedByStaffId != closedByStaffId) {
      return false;
    }
    if (lifecycleStatus != null && closure.lifecycleStatus != lifecycleStatus) {
      return false;
    }
    return true;
  }

  /// Applies this filter to [records], preserving their given order.
  List<OrderClosure> apply(List<OrderClosure> records) {
    return records.where(matches).toList();
  }
}
