/// Lifecycle status of a [CashSession].
///
/// `active` and `rejected` are both "the cashier may still record
/// movements and submit/resubmit a count" states — `SubmitCashCount`
/// accepts either directly into `pendingApproval` (a rejected session
/// never needs a separate "reactivate" step before a recount).
enum CashSessionStatus { active, pendingApproval, approved, rejected, closed }

/// The cash session state machine: which [CashSessionStatus] transitions
/// are valid. Mirrors `OrderStatusTransitions`'s single-source-of-truth
/// shape.
abstract final class CashSessionStatusTransitions {
  CashSessionStatusTransitions._();

  static const Map<CashSessionStatus, Set<CashSessionStatus>> _allowed = {
    CashSessionStatus.active: {CashSessionStatus.pendingApproval},
    CashSessionStatus.pendingApproval: {
      CashSessionStatus.approved,
      CashSessionStatus.rejected,
    },
    CashSessionStatus.rejected: {CashSessionStatus.pendingApproval},
    CashSessionStatus.approved: {CashSessionStatus.closed},
    CashSessionStatus.closed: {},
  };

  static bool canTransition(CashSessionStatus from, CashSessionStatus to) {
    if (from == to) return false;
    return _allowed[from]?.contains(to) ?? false;
  }

  static bool isTerminal(CashSessionStatus status) {
    return (_allowed[status] ?? const {}).isEmpty;
  }
}
