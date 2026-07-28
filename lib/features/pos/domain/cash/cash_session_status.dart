/// Lifecycle status of a [CashSession].
///
/// `active` covers both "movements being recorded" and "a rejected count
/// waiting for a recount" — a session returns to `active` from `rejected`
/// rather than a separate resubmission state, since both are exactly "the
/// cashier may still record movements and submit a count."
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
    CashSessionStatus.rejected: {CashSessionStatus.active},
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
