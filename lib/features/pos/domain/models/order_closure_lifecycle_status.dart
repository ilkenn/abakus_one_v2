/// Lifecycle state of an [OrderClosure] — the order's open/closed/
/// reopened/reclosed history, spanning however many separate
/// [PaymentSession]s that order goes through over its lifetime. Distinct
/// from [PaymentSessionStatus] (one collection attempt's own state) and
/// from `OrderStatus` (the shared, cross-channel order lifecycle) — this
/// tracks the *closure* concern specifically, deliberately kept off both
/// (`docs/decisions.md` ADR-012).
enum OrderClosureLifecycleStatus {
  /// Active, no payment collection has started (or is currently in
  /// progress) for this order.
  open,

  /// A [PaymentSession] is currently collecting for this order.
  paymentInProgress,

  /// Closed for the first time — `reopenCount == 0` when this was reached.
  closed,

  /// Reopened from `closed`/`reclosed` — [OrderClosure.reopenHistory]
  /// carries why/who/when.
  reopened,

  /// Closed again after having been reopened at least once
  /// (`reopenCount >= 1`) — kept distinct from [closed] so the audit
  /// trail can tell "closed the first time" from "closed again after a
  /// correction" at a glance.
  reclosed,

  /// The order itself was cancelled — terminal, no further transitions.
  cancelled,
}

/// The [OrderClosure] state machine — single source of truth, mirroring
/// `OrderStatusTransitions`/`PaymentSessionStatusTransitions`'s existing
/// pattern exactly.
abstract final class OrderClosureLifecycleTransitions {
  OrderClosureLifecycleTransitions._();

  static const Map<OrderClosureLifecycleStatus, Set<OrderClosureLifecycleStatus>>
      _allowed = {
    OrderClosureLifecycleStatus.open: {
      OrderClosureLifecycleStatus.paymentInProgress,
      OrderClosureLifecycleStatus.cancelled,
    },
    OrderClosureLifecycleStatus.paymentInProgress: {
      OrderClosureLifecycleStatus.open,
      OrderClosureLifecycleStatus.closed,
      OrderClosureLifecycleStatus.reclosed,
    },
    OrderClosureLifecycleStatus.closed: {
      OrderClosureLifecycleStatus.reopened,
    },
    OrderClosureLifecycleStatus.reopened: {
      OrderClosureLifecycleStatus.paymentInProgress,
      OrderClosureLifecycleStatus.cancelled,
    },
    OrderClosureLifecycleStatus.reclosed: {
      OrderClosureLifecycleStatus.reopened,
    },
    OrderClosureLifecycleStatus.cancelled: {},
  };

  static bool canTransition(
    OrderClosureLifecycleStatus from,
    OrderClosureLifecycleStatus to,
  ) {
    return _allowed[from]?.contains(to) ?? false;
  }

  static Set<OrderClosureLifecycleStatus> allowedNextStates(
    OrderClosureLifecycleStatus from,
  ) {
    return _allowed[from] ?? const {};
  }
}
