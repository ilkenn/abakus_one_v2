/// A [Delivery]'s operational lifecycle — deliberately separate from
/// `OrderStatus` (which only has the coarse `outForDelivery`), mirroring
/// the same reasoning `PackagePreparationStatus`/`Check`/`PosOrderSession`
/// each already used to stay apart from `Order` (`docs/decisions.md`
/// ADR-013). `Order`/`OrderStatus` is never written by any type in this
/// feature — see `docs/decisions.md` ADR-017 for the documented
/// synchronization boundary between the two.
enum DeliveryStatus {
  created,
  awaitingPackage,
  readyForAssignment,
  assigned,
  accepted,
  arrivedAtRestaurant,
  pickedUp,
  enRoute,
  arrivedAtCustomer,
  delivered,
  assignmentRejected,
  assignmentExpired,
  pickupFailed,
  deliveryFailed,
  cancelled,
  returnedToRestaurant,
  reassigned,
}

/// The delivery state machine. **Completed ([DeliveryStatus.delivered])
/// deliveries are immutable** — terminal, no outgoing transition at all;
/// any later correction is an explicit, separate append-only event
/// (`DeliveryFailure`/`CourierFeedback`/audit entries), never a status
/// mutation of an already-delivered record.
abstract final class DeliveryStatusTransitions {
  DeliveryStatusTransitions._();

  static const Map<DeliveryStatus, Set<DeliveryStatus>> _allowed = {
    DeliveryStatus.created: {
      DeliveryStatus.awaitingPackage,
      DeliveryStatus.cancelled,
    },
    DeliveryStatus.awaitingPackage: {
      DeliveryStatus.readyForAssignment,
      DeliveryStatus.cancelled,
    },
    DeliveryStatus.readyForAssignment: {
      DeliveryStatus.assigned,
      DeliveryStatus.cancelled,
    },
    DeliveryStatus.assigned: {
      DeliveryStatus.accepted,
      DeliveryStatus.assignmentRejected,
      DeliveryStatus.assignmentExpired,
      DeliveryStatus.cancelled,
    },
    DeliveryStatus.assignmentRejected: {
      DeliveryStatus.readyForAssignment, // re-offered to another courier
    },
    DeliveryStatus.assignmentExpired: {
      DeliveryStatus.readyForAssignment,
    },
    DeliveryStatus.accepted: {
      DeliveryStatus.arrivedAtRestaurant,
      DeliveryStatus.reassigned,
      DeliveryStatus.cancelled,
    },
    DeliveryStatus.arrivedAtRestaurant: {
      DeliveryStatus.pickedUp,
      DeliveryStatus.pickupFailed,
      DeliveryStatus.reassigned,
    },
    DeliveryStatus.pickupFailed: {
      DeliveryStatus.arrivedAtRestaurant,
      DeliveryStatus.returnedToRestaurant,
    },
    DeliveryStatus.pickedUp: {
      DeliveryStatus.enRoute,
    },
    DeliveryStatus.enRoute: {
      DeliveryStatus.arrivedAtCustomer,
      DeliveryStatus.deliveryFailed,
    },
    DeliveryStatus.arrivedAtCustomer: {
      DeliveryStatus.delivered,
      DeliveryStatus.deliveryFailed,
    },
    DeliveryStatus.deliveryFailed: {
      DeliveryStatus.returnedToRestaurant,
      DeliveryStatus.enRoute, // retry, e.g. customer reachable again
    },
    DeliveryStatus.reassigned: {
      DeliveryStatus.readyForAssignment,
    },
    DeliveryStatus.returnedToRestaurant: {},
    DeliveryStatus.delivered: {},
    DeliveryStatus.cancelled: {},
  };

  static bool canTransition(DeliveryStatus from, DeliveryStatus to) {
    if (from == to) return false;
    return _allowed[from]?.contains(to) ?? false;
  }

  static bool isTerminal(DeliveryStatus status) {
    return (_allowed[status] ?? const {}).isEmpty;
  }
}
