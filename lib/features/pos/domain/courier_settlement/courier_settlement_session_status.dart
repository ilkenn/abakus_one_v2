/// Lifecycle status of a [CourierSettlementSession] — the courier's
/// *financial settlement* status, deliberately separate from any courier
/// *operational* status (on-shift/delivering/off-shift). No operational
/// status model exists in this codebase (`docs/business_rules.md`
/// BR-COURIER-004 — courier roster/dispatch is ROADMAP, no code), so this
/// enum tracks only what this sprint actually owns: the financial
/// reconciliation of cash a courier is holding.
///
/// Shape mirrors `CashSessionStatus` exactly, including `rejected ->
/// pendingApproval` (a rejected declaration is recounted with a fresh
/// `SubmitCourierCashDeclaration` call, no separate reactivate step).
enum CourierSettlementSessionStatus {
  active,
  pendingApproval,
  approved,
  rejected,
  closed,
}

/// The courier settlement session state machine — mirrors
/// `CashSessionStatusTransitions`'s single-source-of-truth shape.
abstract final class CourierSettlementSessionStatusTransitions {
  CourierSettlementSessionStatusTransitions._();

  static const Map<CourierSettlementSessionStatus,
      Set<CourierSettlementSessionStatus>> _allowed = {
    CourierSettlementSessionStatus.active: {
      CourierSettlementSessionStatus.pendingApproval,
    },
    CourierSettlementSessionStatus.pendingApproval: {
      CourierSettlementSessionStatus.approved,
      CourierSettlementSessionStatus.rejected,
    },
    CourierSettlementSessionStatus.rejected: {
      CourierSettlementSessionStatus.pendingApproval,
    },
    CourierSettlementSessionStatus.approved: {
      CourierSettlementSessionStatus.closed,
    },
    CourierSettlementSessionStatus.closed: {},
  };

  static bool canTransition(
    CourierSettlementSessionStatus from,
    CourierSettlementSessionStatus to,
  ) {
    if (from == to) return false;
    return _allowed[from]?.contains(to) ?? false;
  }

  static bool isTerminal(CourierSettlementSessionStatus status) {
    return (_allowed[status] ?? const {}).isEmpty;
  }
}
