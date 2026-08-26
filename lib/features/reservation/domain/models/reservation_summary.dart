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
    required this.productId,
    required this.productName,
    required this.quantity,
    required this.modifierNames,
    required this.lineTotalMinorUnits,
  });

  /// Boncuk Loyalty P7-D (2026-08-24) — the canonical `menuProducts` id,
  /// `null` for a Bowl Builder line (no real canonical id exists for those,
  /// see `submitTakeawayOrder.ts`'s own `findFirstEligibleCartProductId`
  /// doc comment). Used to cross-reference a redeemed catalog reward's own
  /// `redeemedProductId` back to its display name, never the other way
  /// around.
  final String? productId;
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
    this.catalogRewardTitle,
    this.catalogRewardBoncukCost,
    this.catalogRewardRedeemedProductId,
    this.catalogRewardCoveredValueMinorUnits,
    this.campaignTitle,
    this.campaignDiscountMinorUnits,
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

  /// Boncuk Loyalty Program P7-D (2026-08-24) — the catalog-reward sibling
  /// of the Boncuk fields above, sourced directly from the canonical
  /// order's own immutable `catalogReward` snapshot — never re-derived
  /// from the current live Reward Catalog, so a later reward edit can
  /// never rewrite this preorder's own history. `null` means no catalog
  /// reward was redeemed against this preorder.
  final String? catalogRewardTitle;
  final int? catalogRewardBoncukCost;
  final String? catalogRewardRedeemedProductId;
  final int? catalogRewardCoveredValueMinorUnits;

  bool get hasCatalogRewardSummary =>
      catalogRewardTitle != null &&
      catalogRewardBoncukCost != null &&
      catalogRewardRedeemedProductId != null &&
      catalogRewardCoveredValueMinorUnits != null;

  /// The redeemed product's display name, cross-referenced from this SAME
  /// preorder's own [lines] — never a separate catalog lookup, matching
  /// `TakeawayCheckoutScreen`'s own identical cross-referencing discipline.
  /// `null` if [hasCatalogRewardSummary] is false or (defensively) the
  /// line can no longer be found.
  String? get catalogRewardRedeemedProductName {
    final productId = catalogRewardRedeemedProductId;
    if (productId == null) return null;
    for (final line in lines) {
      if (line.productId == productId) return line.productName;
    }
    return null;
  }

  /// Server-Authoritative Campaign Engine P8-C.2 (2026-08-25) — the
  /// campaign sibling of the Boncuk/catalog-reward summaries above, sourced
  /// directly from the canonical preorder order's own immutable `campaign`
  /// snapshot — never re-derived from the current live Campaign document,
  /// so a later campaign edit (title/version) can never rewrite this
  /// preorder's own history. `null` means no campaign was applied to this
  /// preorder. Mutually exclusive with [hasBoncukSummary]/
  /// [hasCatalogRewardSummary] (one order = one benefit).
  final String? campaignTitle;
  final int? campaignDiscountMinorUnits;

  bool get hasCampaignSummary =>
      campaignTitle != null && campaignDiscountMinorUnits != null;
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
