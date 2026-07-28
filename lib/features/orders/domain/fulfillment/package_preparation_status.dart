/// Operational stage of physically preparing/packaging an [Order] for
/// handover — deliberately a **separate state machine from
/// [OrderStatus]**, not an extension of it.
///
/// `OrderStatus` is the shared, channel-agnostic lifecycle every future
/// Kitchen/Courier/Admin consumer depends on (`docs/order_lifecycle_
/// architecture.md`); folding 13 packaging/delivery-prep sub-states into
/// it would conflate "where is this order in its cross-channel lifecycle"
/// with "how far along is packaging" — two different questions (an order
/// can be `OrderStatus.preparing` while packaging is still `received`).
/// This mirrors the same separation already used for `PosOrderSession`
/// (kept apart from `Order`) and `OrderClosure` (kept apart from `Order`),
/// not a new pattern (`docs/decisions.md` ADR-013).
enum PackagePreparationStatus {
  received,
  pendingAcceptance,
  accepted,
  preparing,
  readyForPacking,
  packing,
  packed,
  waitingForCourier,
  courierCollected,
  outForDelivery,
  delivered,
  cancelled,
  exception,
}

/// The package-preparation state machine: which
/// [PackagePreparationStatus] transitions are valid.
///
/// Mirrors `OrderStatusTransitions`'s single-source-of-truth shape.
/// [PackagePreparationStatus.packed] may go straight to
/// [PackagePreparationStatus.delivered] (a takeaway/dine-in handover with
/// no courier leg) or to [PackagePreparationStatus.waitingForCourier] (a
/// delivery order) — both are valid from the same state, since which one
/// applies depends on the order's channel, not on packaging itself.
abstract final class PackagePreparationTransitions {
  PackagePreparationTransitions._();

  static const Map<PackagePreparationStatus, Set<PackagePreparationStatus>>
      _allowed = {
    PackagePreparationStatus.received: {
      PackagePreparationStatus.pendingAcceptance,
      PackagePreparationStatus.cancelled,
    },
    PackagePreparationStatus.pendingAcceptance: {
      PackagePreparationStatus.accepted,
      PackagePreparationStatus.cancelled,
    },
    PackagePreparationStatus.accepted: {
      PackagePreparationStatus.preparing,
      PackagePreparationStatus.cancelled,
    },
    PackagePreparationStatus.preparing: {
      PackagePreparationStatus.readyForPacking,
      PackagePreparationStatus.cancelled,
      PackagePreparationStatus.exception,
    },
    PackagePreparationStatus.readyForPacking: {
      PackagePreparationStatus.packing,
      PackagePreparationStatus.exception,
    },
    PackagePreparationStatus.packing: {
      PackagePreparationStatus.packed,
      PackagePreparationStatus.exception,
    },
    PackagePreparationStatus.packed: {
      PackagePreparationStatus.waitingForCourier,
      PackagePreparationStatus.delivered,
      PackagePreparationStatus.exception,
    },
    PackagePreparationStatus.waitingForCourier: {
      PackagePreparationStatus.courierCollected,
      PackagePreparationStatus.exception,
    },
    PackagePreparationStatus.courierCollected: {
      PackagePreparationStatus.outForDelivery,
      PackagePreparationStatus.exception,
    },
    PackagePreparationStatus.outForDelivery: {
      PackagePreparationStatus.delivered,
      PackagePreparationStatus.exception,
    },
    PackagePreparationStatus.delivered: {},
    PackagePreparationStatus.cancelled: {},
    PackagePreparationStatus.exception: {
      PackagePreparationStatus.preparing,
      PackagePreparationStatus.cancelled,
    },
  };

  static bool canTransition(
    PackagePreparationStatus from,
    PackagePreparationStatus to,
  ) {
    if (from == to) return false;
    return _allowed[from]?.contains(to) ?? false;
  }

  static bool isTerminal(PackagePreparationStatus status) {
    return (_allowed[status] ?? const {}).isEmpty;
  }
}
