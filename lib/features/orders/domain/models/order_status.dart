/// Canonical, channel-agnostic lifecycle state of an order.
///
/// This is the machine-readable state every channel (QR table orders, POS,
/// takeaway, delivery, reservation preorders) and every future backend/
/// kitchen/courier integration is meant to share. It intentionally does not
/// replace [OrderModel.status] (a free-form, already-localized display
/// string the current order-history UI reads directly) — see
/// `docs/order_lifecycle_architecture.md` for why both fields coexist.
enum OrderStatus {
  created,
  pendingConfirmation,
  confirmed,
  preparing,
  ready,
  outForDelivery,
  served,
  completed,
  cancelled,
  rejected,
  refunded,

  /// AP-6 Sprint 1 — a takeaway order accepted while the branch's
  /// [BranchTakeawaySettings] was `paused`. Distinct from
  /// [pendingConfirmation]: nobody is being asked to make a staff
  /// decision — the order is already accepted, just deliberately held
  /// back from the kitchen until `scheduledFor` (a server-side sweep,
  /// `takeawayOperationsSweep.ts`, promotes it to [confirmed] once due).
  /// Never confused with `PickupMode.scheduled`
  /// (`lib/features/orders/domain/models/pickup_mode.dart`) — that's the
  /// customer's own chosen pickup time, a completely different axis that
  /// can be set independently of this status.
  scheduled,

  /// AP-6 Sprint 3 — a consortium/external-merchant delivery order
  /// (`Order.merchantId` set), written directly at this status by
  /// `registerConsortiumOrder.ts`: our own kitchen never touches it, so it
  /// never passes through [pendingConfirmation]/[confirmed]/[preparing]/
  /// [ready] at all — it starts life already ready for a courier to pick
  /// up from the external merchant's own [Order.pickupAddress]. **Never
  /// confused with the unrelated `PackagePreparationStatus`/
  /// `PackageNotReadyForPickupViolation` vocabulary in
  /// `features/courier/application/use_cases/confirm_package_pickup.dart`**
  /// — that's a courier's own pickup-confirmation action on a `Delivery`
  /// aggregate, an entirely different axis from this order-lifecycle
  /// status.
  readyForPickup,
}

/// The order state machine: which [OrderStatus] transitions are valid.
///
/// Kept as a single source of truth so no caller (UI, future backend,
/// kitchen/POS integrations) can invent an ad-hoc, inconsistent status flow.
/// See `docs/order_lifecycle_architecture.md` §1 for the full transition
/// table and the reasoning behind each edge.
abstract final class OrderStatusTransitions {
  OrderStatusTransitions._();

  static const Map<OrderStatus, Set<OrderStatus>> _allowed = {
    OrderStatus.created: {
      OrderStatus.pendingConfirmation,
      OrderStatus.cancelled,
      OrderStatus.rejected,
    },
    OrderStatus.pendingConfirmation: {
      OrderStatus.confirmed,
      OrderStatus.rejected,
      OrderStatus.cancelled,
    },
    OrderStatus.confirmed: {
      OrderStatus.preparing,
      OrderStatus.cancelled,
    },
    OrderStatus.preparing: {
      OrderStatus.ready,
      OrderStatus.cancelled,
    },
    OrderStatus.ready: {
      OrderStatus.outForDelivery,
      OrderStatus.served,
      OrderStatus.completed,
      OrderStatus.cancelled,
    },
    OrderStatus.outForDelivery: {
      OrderStatus.served,
      OrderStatus.completed,
      OrderStatus.cancelled,
    },
    OrderStatus.served: {
      OrderStatus.completed,
    },
    OrderStatus.completed: {
      OrderStatus.refunded,
    },
    OrderStatus.cancelled: {},
    OrderStatus.rejected: {},
    OrderStatus.refunded: {},
    OrderStatus.scheduled: {
      OrderStatus.confirmed,
      OrderStatus.rejected,
      OrderStatus.cancelled,
    },
    OrderStatus.readyForPickup: {
      OrderStatus.outForDelivery,
      OrderStatus.cancelled,
      OrderStatus.rejected,
    },
  };

  /// Whether moving from [from] directly to [to] is a valid transition.
  /// A status "transitioning" to itself is never valid — that's a no-op,
  /// not a state change.
  static bool canTransition(OrderStatus from, OrderStatus to) {
    if (from == to) return false;
    return _allowed[from]?.contains(to) ?? false;
  }

  /// The set of states reachable directly from [from]. Empty for a
  /// terminal state.
  static Set<OrderStatus> allowedNextStates(OrderStatus from) {
    return _allowed[from] ?? const {};
  }

  /// Whether [status] has no further valid transitions.
  static bool isTerminal(OrderStatus status) {
    return (_allowed[status] ?? const {}).isEmpty;
  }
}

/// Maps a canonical [OrderStatus] onto the legacy, localized
/// [OrderModel.status] display string the pre-existing order-history UI
/// (`orders_screen.dart`, `order_detail_screen.dart`) reads directly.
///
/// This is the single place that bridges the two fields described in
/// `docs/order_lifecycle_architecture.md` §1 — introduced by the Active
/// Order Tracking phase so a [lifecycleStatus] transition made through
/// `OrdersNotifier.updateLifecycleStatus` stays visible/coherent on the
/// legacy screens too, instead of only being reflected in the new
/// `OrderTrackingTimeline` projection those screens don't read.
abstract final class OrderStatusLegacyLabel {
  OrderStatusLegacyLabel._();

  /// The legacy label [status] should be displayed as. Chosen, where
  /// possible, to match strings the legacy screens already recognize
  /// (`'Onay Bekliyor'`/`'Onaylandı'`/`'Hazırlanıyor'`/`'Teslim
  /// Edildi'`/`'İptal Edildi'`) so their existing `status == '...'`
  /// branches (cancel-eligibility, review-eligibility, list coloring)
  /// keep working without modification.
  static String forStatus(OrderStatus status) {
    switch (status) {
      case OrderStatus.created:
      case OrderStatus.pendingConfirmation:
      // AP-6 Sprint 1 — a scheduled order is already accepted, but from
      // the customer's own legacy-screen perspective ("has this started
      // being made yet?") the honest answer is still no, same as
      // pendingConfirmation — including the same cancel-eligibility
      // behavior those screens already gate on this exact string.
      case OrderStatus.scheduled:
        return 'Onay Bekliyor';
      case OrderStatus.confirmed:
        return 'Onaylandı';
      case OrderStatus.preparing:
      case OrderStatus.ready:
      // AP-6 Sprint 3 — a consortium order has no real customer-facing
      // legacy screen (no customerId at all), but the honest nearest
      // legacy bucket is the same "being made ready" string as
      // preparing/ready.
      case OrderStatus.readyForPickup:
        return 'Hazırlanıyor';
      case OrderStatus.outForDelivery:
        return 'Yolda';
      case OrderStatus.served:
      case OrderStatus.completed:
      case OrderStatus.refunded:
        return 'Teslim Edildi';
      case OrderStatus.cancelled:
      case OrderStatus.rejected:
        return 'İptal Edildi';
    }
  }
}
