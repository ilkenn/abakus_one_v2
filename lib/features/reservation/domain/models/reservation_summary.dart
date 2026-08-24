import 'reservation_status.dart';

/// The denormalized active-proposal snapshot `respondToReservation.ts`'s
/// `handleProposeChange` writes directly onto the `Reservation` document
/// (Faz R.2) — `reservationChangeProposals` itself stays org-staff-read-
/// only (Faz R.1B's own scope decision, unchanged), so the customer-facing
/// change-proposal UX reads these fields instead of a second collection.
class ReservationProposalSnapshot {
  const ReservationProposalSnapshot({
    required this.proposedTime,
    required this.proposedAreaId,
    required this.customerResponseDeadlineAt,
  });

  final DateTime proposedTime;
  final String proposedAreaId;
  final DateTime customerResponseDeadlineAt;

  bool get isExpired => DateTime.now().isAfter(customerResponseDeadlineAt);
}

/// Mirrors the backend's `Order.status` for a `reservationPreorder`
/// order. Boncuk Loyalty P6-B (2026-08-24) — extended with the full
/// canonical post-release kitchen pipeline (`preparing`/`ready`/`served`/
/// `completed`) plus `refunded`, now that `advanceReservationPreorderOrderStatus`/
/// `refundReservationPreorderOrder` actually drive an order through them;
/// `rejected` is included for completeness (the generic `OrderStatus` enum
/// has it, even though a reservation preorder always reaches its
/// pre-release terminal state via `cancelled`, never `rejected`, per
/// `reservationPreorder.ts`'s own `buildPreorderCancellationPatch`).
enum ReservationPreorderStatus {
  pendingConfirmation,
  confirmed,
  preparing,
  ready,
  served,
  completed,
  cancelled,
  rejected,
  refunded;

  static ReservationPreorderStatus fromName(String name) =>
      ReservationPreorderStatus.values.byName(name);
}

class ReservationPreorderLineSummary {
  const ReservationPreorderLineSummary({
    required this.productName,
    required this.quantity,
    required this.modifierNames,
    required this.lineTotalMinorUnits,
  });

  final String productName;
  final int quantity;
  final List<String> modifierNames;
  final int lineTotalMinorUnits;
}

class ReservationPreorderSummary {
  const ReservationPreorderSummary({
    required this.orderId,
    required this.status,
    required this.kitchenReleaseAt,
    required this.lines,
    required this.grandTotalMinorUnits,
    this.boncukUsed,
    this.boncukValueMinorUnits,
    this.remainingPayableMinorUnits,
  });

  final String orderId;
  final ReservationPreorderStatus status;
  final DateTime? kitchenReleaseAt;
  final List<ReservationPreorderLineSummary> lines;
  final int grandTotalMinorUnits;

  /// Boncuk Loyalty Program P6-B (2026-08-24) — additive, optional
  /// server-confirmed redemption summary, sourced directly from the
  /// canonical order's own `boncukRedemption` map (never a pre-submit
  /// estimate). `null` (the default) means no Boncuk was redeemed against
  /// this preorder — mirrors `OrderSuccessScreen`'s own
  /// `orderTotalMinorUnits`/`boncukUsed`/`boncukValueMinorUnits`/
  /// `remainingPayableMinorUnits` optional-additive-field convention.
  final int? boncukUsed;
  final int? boncukValueMinorUnits;
  final int? remainingPayableMinorUnits;

  bool get hasBoncukSummary =>
      boncukUsed != null &&
      boncukValueMinorUnits != null &&
      remainingPayableMinorUnits != null;
}

/// The customer-facing read model for their own reservation — sourced
/// directly from `reservations/{id}` (owner-readable in `firestore.rules`)
/// plus, when a preorder exists, `orders/{preorderOrderId}` (also owner-
/// readable via `customerId == request.auth.uid`). Never exposes internal
/// ids (hold ids, bucket ids) — those simply aren't read into this model.
class ReservationSummary {
  const ReservationSummary({
    required this.id,
    required this.status,
    required this.partySize,
    required this.requestedTime,
    required this.requestedAreaId,
    this.confirmedTime,
    this.confirmedAreaId,
    this.activeProposalId,
    this.activeProposal,
    this.preorder,
  });

  final String id;
  final ReservationStatus status;
  final int partySize;
  final DateTime requestedTime;
  final String requestedAreaId;
  final DateTime? confirmedTime;
  final String? confirmedAreaId;

  /// The real, canonical `reservationChangeProposals` document id — the
  /// original (non-denormalized) `Reservation.activeProposalId` field,
  /// required to actually call `respondToProposedChange`.
  final String? activeProposalId;

  /// The denormalized proposed-time/area/deadline snapshot (Faz R.2) —
  /// display-only; [activeProposalId] is the one used for the actual
  /// accept/reject call.
  final ReservationProposalSnapshot? activeProposal;
  final ReservationPreorderSummary? preorder;
}
