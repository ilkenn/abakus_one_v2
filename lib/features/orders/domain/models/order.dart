import '../../../../core/errors/business_rule_violation.dart';
import '../../../payment/domain/models/payment_method_snapshot.dart';
import '../pricing/price_breakdown.dart';
import 'boncuk_redemption_snapshot.dart';
import 'campaign_snapshot.dart';
import 'catalog_reward_snapshot.dart';
import 'courier_visibility.dart';
import 'delivery_address_snapshot.dart';
import 'order_actor.dart';
import 'order_audit_entry.dart';
import 'order_benefit_type.dart';
import 'order_channel.dart';
import 'order_id.dart';
import 'order_line.dart';
import 'order_number.dart';
import 'order_status.dart';
import 'order_timestamps.dart';
import 'pickup_mode.dart';

/// The shared order aggregate — the domain foundation POS, Kitchen Display,
/// Courier, Customer App, and Admin are all meant to build on.
///
/// **Deliberately a new, separate type from the legacy `OrderModel`**
/// (`order_model.dart`) — approved architecture decision, Phase 3
/// Sprint 3A. `OrderModel` mixes the canonical lifecycle fields with a
/// large block of customer-app-specific UI fields (delivery-instruction
/// flags, review/rating fields, ...) that have no place in an aggregate
/// meant to be shared across every channel and every staff-facing surface.
/// This sprint does not migrate or replace `OrderModel`; that's separate,
/// future, out-of-scope work.
///
/// Reuses every existing shared building block rather than duplicating
/// one: [OrderStatus]/`OrderStatusTransitions` (the 11-state machine),
/// [OrderChannel], [OrderActor], [CourierVisibility], [OrderTimestamps],
/// and [OrderAuditEntry] — the last of these **is** this aggregate's
/// immutable status history (see [statusHistory]'s doc comment); no
/// second, parallel history type was introduced.
class Order {
  const Order({
    required this.id,
    required this.orderNumber,
    required this.status,
    required this.channel,
    required this.branchId,
    required this.restaurantId,
    this.customerId,
    this.tableId,
    this.tableSessionId,
    this.guestSessionId,
    this.guestAuthUid,
    this.reservationContextId,
    this.takeawayEntrySessionId,
    this.pickupMode,
    this.pickupTime,
    this.contactFirstName,
    this.contactLastName,
    this.contactPhone,
    this.courierVisibility = CourierVisibility.hidden,
    required this.lines,
    required this.pricing,
    this.statusHistory = const [],
    this.version = 1,
    required this.timestamps,
    this.customerNote = '',
    this.kitchenNote = '',
    this.deliveryAddressSnapshot,
    this.paymentMethodSnapshot,
    this.selectedBenefitType = OrderBenefitType.none,
    this.boncukRedemption,
    this.catalogReward,
    this.campaign,
  }) : assert(
          pickupMode != PickupMode.scheduled || pickupTime != null,
          'pickupMode == PickupMode.scheduled requires a non-null pickupTime',
        );

  final OrderId id;
  final OrderNumber orderNumber;
  final OrderStatus status;
  final OrderChannel channel;

  final String branchId;
  final String restaurantId;

  /// `null` for a guest/anonymous order (e.g. an unauthenticated QR table
  /// visit) — see `GuestSession.authenticatedUserId` for the same
  /// optionality pattern.
  final String? customerId;

  /// Table/session references — all optional, `null` for a channel with
  /// no table context (takeaway, delivery). Field names deliberately match
  /// `TableSession`/`GuestSession`'s own id fields, not new vocabulary.
  final String? tableId;
  final String? tableSessionId;
  final String? guestSessionId;

  /// The raw Firebase Auth uid that technically submitted a `dineInQr`
  /// order — Phase 3.1 (`docs/decisions.md`, Table Guest Session). Set
  /// for **every** `dineInQr` order, regardless of [customerId]: an
  /// anonymous guest and an already-signed-in real customer both get
  /// this field populated with whatever uid
  /// `TechnicalIdentityProvider.ensureSignedIn()` actually returned —
  /// [customerId] separately records whether that uid also happens to be
  /// a real, phone-verified Abaküs customer (`null` if not).
  ///
  /// This is deliberately **independent of [customerId]** so that order
  /// *ownership* (who may read this order back) never depends on the
  /// `tableGuestSessions` document that authorized its *creation* still
  /// existing — a session record can expire or be cleaned up later
  /// without retroactively hiding a guest's own order history for their
  /// visit. `null` for every non-`dineInQr` order (delivery, takeaway,
  /// staff-created dine-in) — this field has no meaning outside the
  /// Table Guest Session flow.
  final String? guestAuthUid;

  /// The Reservation aggregate this order is scoped to, server-generated
  /// and immutable — populated one of two ways, never a customer-supplied
  /// value in either:
  ///
  /// 1. **`dineInQr` orders (Faz R.1C.2 §11/§14)**: a snapshot of the
  ///    `activeReservationTableContext` that was live on this order's table
  ///    at the moment its `tableGuestSessions` document was opened. `null`
  ///    for the ordinary walk-in case. Firestore Security Rules require
  ///    this to exactly equal the originating
  ///    `tableGuestSessions.reservationContextId` (`null` included) for the
  ///    two dine-in-QR order-create branches — see `firestore.rules`'
  ///    `tableGuestSessionMatchesOrderScope`. **Never** derived from
  ///    [customerId]/[guestAuthUid] here — a table context is operational
  ///    table-state, not an identity (Faz R.1C.2 §16's own explicit
  ///    identity-invariant boundary).
  /// 2. **`reservationPreorder` orders (Faz R.1D.1 §5)**: the id of the
  ///    `Reservation` this preorder was created for, set directly to
  ///    `Reservation.id` by `submitReservation`'s own Admin-SDK transaction
  ///    (which bypasses Firestore Rules entirely — the `dineInQr`-scoped
  ///    rule above never evaluates this channel). This *does* originate
  ///    from the same authenticated customer creating the order
  ///    ([customerId] is that customer's own uid for this channel), unlike
  ///    case 1 above — a preorder's reservation link is a direct
  ///    same-actor relation, not a table-state snapshot.
  ///
  /// `null` for every order that is neither of the above (delivery,
  /// takeaway, staff-created dine-in) — this field has no meaning outside
  /// these two flows.
  final String? reservationContextId;

  /// A reference to the server-resolved Gel Al (takeaway) entry
  /// session/token record a guest kiosk-QR order was authorized under —
  /// the takeaway-flow analogue of [guestSessionId], not the raw scanned
  /// token itself (that resolution/token architecture is separate, future
  /// work — this field only reserves where the reference will live once it
  /// exists). `null` for every order not created through that flow,
  /// including an authenticated in-app takeaway order (Scenario 2 uses the
  /// customer's own [customerId], not an entry session) and every
  /// dine-in/delivery/staff order.
  final String? takeawayEntrySessionId;

  /// How a takeaway order's [pickupTime] was chosen — see [PickupMode].
  /// `null` for every non-takeaway order.
  final PickupMode? pickupMode;

  /// The requested pickup time for a takeaway order. Required (non-null) by
  /// this class's own constructor assertion when [pickupMode] is
  /// [PickupMode.scheduled]; may be `null` when [pickupMode] is
  /// [PickupMode.asap] (the customer is already present, or wants the
  /// earliest possible time). `null` for every non-takeaway order.
  ///
  /// Frozen at order-creation time, like every other line/pricing value on
  /// this aggregate — server-authoritative validation that it is actually
  /// achievable (Europe/Istanbul "now + 20 minutes" or later) is separate,
  /// future work (`docs/business_rules.md` BR-PRICE-002's same
  /// not-yet-enforced caveat applies here).
  final DateTime? pickupTime;

  /// Immutable contact-data snapshot for a guest Gel Al order (Scenario
  /// 1 — no account, no `customerId`) — **not** an identity or
  /// authorization source, only order/contact data captured at checkout
  /// time, the same way [OrderLine.productName] snapshots a product name
  /// rather than trusting a live catalog lookup later. Reused as-is for an
  /// authenticated in-app takeaway order (Scenario 2) rather than a
  /// duplicate customer-profile field, per explicit product direction —
  /// both flows populate the same three fields.
  ///
  /// All three are `null` together for every order that isn't a takeaway
  /// order collecting contact data at checkout.
  final String? contactFirstName;
  final String? contactLastName;
  final String? contactPhone;

  /// See [CourierVisibility]'s own doc comment for the privacy rule this
  /// preserves verbatim from the existing customer-app implementation —
  /// reaching [OrderStatus.outForDelivery] alone must never imply this is
  /// [CourierVisibility.visibleToCustomer].
  final CourierVisibility courierVisibility;

  final List<OrderLine> lines;
  final PriceBreakdown pricing;

  /// This aggregate's immutable status history — append-only, one
  /// [OrderAuditEntry.statusChange] per transition made via
  /// [transitionTo]. Deliberately not a second, order-specific history
  /// type: [OrderAuditEntry] already is exactly this (actor/timestamp/
  /// previous-value/new-value), reused rather than duplicated.
  final List<OrderAuditEntry> statusHistory;

  /// Optimistic-concurrency version, starting at 1 and incrementing by 1
  /// on every [transitionTo] call — groundwork for a future backend sync/
  /// conflict-detection layer, not consumed by anything in this sprint.
  final int version;

  final OrderTimestamps timestamps;

  /// Order-level note from the customer — distinct from any individual
  /// [OrderLine.customerNote]. Empty by default; additive field (Phase 3
  /// Sprint 3B) so every existing caller/test built before it still
  /// compiles and behaves identically.
  final String customerNote;

  /// Order-level instruction for the kitchen — distinct from any
  /// individual [OrderLine.kitchenNote]. Same additive-field reasoning as
  /// [customerNote].
  final String kitchenNote;

  /// The frozen delivery address for a [OrderChannel.delivery] order —
  /// Faz P.1, additive/nullable so every existing channel and every
  /// existing caller/test built before it still compiles and behaves
  /// identically. `null` for every non-delivery order.
  ///
  /// **P.1 does not create a real delivery [Order] using this field** — no
  /// production code path in this phase constructs one (see
  /// [DeliveryAddressSnapshot]'s own doc comment for why: it requires a
  /// server-verified address, and no verification provider exists yet).
  /// This field exists so the aggregate shape is ready for P.2/P.3 to
  /// populate once that provider does.
  final DeliveryAddressSnapshot? deliveryAddressSnapshot;

  /// The frozen payment method for this order — Faz P.1, additive/nullable
  /// same as [deliveryAddressSnapshot]. Reuses the existing payment-domain
  /// snapshot type (`docs/decisions.md` ADR-012) rather than a new,
  /// order-specific one — see [PaymentMethodSnapshot]'s own doc comment
  /// for why a frozen snapshot (not a live [PaymentMethod] reference) is
  /// required for any historical order. `null` for every order that
  /// hasn't recorded a payment method yet — not delivery-specific by
  /// itself, though P.1's only populated use is the delivery flow.
  final PaymentMethodSnapshot? paymentMethodSnapshot;

  /// Which single benefit (if any) settled part of this order's total —
  /// Boncuk Loyalty Program P4-E-B (2026-08-22). [OrderBenefitType.none] by
  /// default, matching every order that predates this field and every
  /// order that simply never redeemed anything. Server-authoritative only
  /// — never set from local/client state; see [OrderBenefitType]'s own doc
  /// comment for the exact closed set.
  final OrderBenefitType selectedBenefitType;

  /// The server-computed Boncuk redemption snapshot when
  /// [selectedBenefitType] is [OrderBenefitType.boncukRedemption]; `null`
  /// otherwise, including every pre-P4-E-B order (additive/nullable, same
  /// backward-compatibility contract as [deliveryAddressSnapshot]/
  /// [paymentMethodSnapshot]). See [BoncukRedemptionSnapshot]'s own doc
  /// comment — settlement, never a discount; [pricing] is never touched by
  /// this field.
  final BoncukRedemptionSnapshot? boncukRedemption;

  /// The server-computed Reward Catalog redemption snapshot when
  /// [selectedBenefitType] is [OrderBenefitType.catalogReward]; `null`
  /// otherwise, including every pre-P7-C order (additive/nullable, same
  /// backward-compatibility contract as [boncukRedemption]). See
  /// [CatalogRewardSnapshot]'s own doc comment — unlike [boncukRedemption],
  /// this reflects a genuine, already-applied price reduction on the
  /// relevant [OrderLine], not a settlement layered on top of an unchanged
  /// total.
  final CatalogRewardSnapshot? catalogReward;

  /// The server-computed Campaign redemption snapshot when
  /// [selectedBenefitType] is [OrderBenefitType.campaign]; `null`
  /// otherwise, including every pre-P8-C order (additive/nullable, same
  /// backward-compatibility contract as [boncukRedemption]/[catalogReward]).
  /// See [CampaignSnapshot]'s own doc comment — like [catalogReward], this
  /// reflects a genuine, already-applied price reduction, not a settlement
  /// layered on top of an unchanged total.
  final CampaignSnapshot? campaign;

  /// Moves this order from [status] to [newStatus], appending a new
  /// [OrderAuditEntry.statusChange] to [statusHistory] and recording the
  /// timestamp via [OrderTimestamps.recordedAt].
  ///
  /// Throws [InvalidOrderStatusTransitionViolation] if
  /// `OrderStatusTransitions.canTransition(status, newStatus)` is `false`
  /// — this is the one and only place an `Order`'s status may change, so
  /// every transition is guaranteed to have gone through that check.
  ///
  /// [auditEntryId] is externally supplied, matching [OrderId]/
  /// [OrderNumber]'s "no ID generation in this codebase" reasoning.
  Order transitionTo(
    OrderStatus newStatus, {
    required OrderActor actor,
    required DateTime at,
    required String auditEntryId,
  }) {
    if (!OrderStatusTransitions.canTransition(status, newStatus)) {
      throw InvalidOrderStatusTransitionViolation(
        fromStatusName: status.name,
        toStatusName: newStatus.name,
      );
    }
    final entry = OrderAuditEntry.statusChange(
      id: auditEntryId,
      from: status,
      to: newStatus,
      actor: actor,
      at: at,
    );
    return copyWith(
      status: newStatus,
      statusHistory: [...statusHistory, entry],
      version: version + 1,
      timestamps: timestamps.recordedAt(newStatus, at),
    );
  }

  Order copyWith({
    OrderId? id,
    OrderNumber? orderNumber,
    OrderStatus? status,
    OrderChannel? channel,
    String? branchId,
    String? restaurantId,
    String? customerId,
    String? tableId,
    String? tableSessionId,
    String? guestSessionId,
    String? guestAuthUid,
    String? reservationContextId,
    String? takeawayEntrySessionId,
    PickupMode? pickupMode,
    DateTime? pickupTime,
    String? contactFirstName,
    String? contactLastName,
    String? contactPhone,
    CourierVisibility? courierVisibility,
    List<OrderLine>? lines,
    PriceBreakdown? pricing,
    List<OrderAuditEntry>? statusHistory,
    int? version,
    OrderTimestamps? timestamps,
    String? customerNote,
    String? kitchenNote,
    DeliveryAddressSnapshot? deliveryAddressSnapshot,
    PaymentMethodSnapshot? paymentMethodSnapshot,
    OrderBenefitType? selectedBenefitType,
    BoncukRedemptionSnapshot? boncukRedemption,
    CatalogRewardSnapshot? catalogReward,
    CampaignSnapshot? campaign,
  }) {
    return Order(
      id: id ?? this.id,
      orderNumber: orderNumber ?? this.orderNumber,
      status: status ?? this.status,
      channel: channel ?? this.channel,
      branchId: branchId ?? this.branchId,
      restaurantId: restaurantId ?? this.restaurantId,
      customerId: customerId ?? this.customerId,
      tableId: tableId ?? this.tableId,
      tableSessionId: tableSessionId ?? this.tableSessionId,
      guestSessionId: guestSessionId ?? this.guestSessionId,
      guestAuthUid: guestAuthUid ?? this.guestAuthUid,
      reservationContextId: reservationContextId ?? this.reservationContextId,
      takeawayEntrySessionId:
          takeawayEntrySessionId ?? this.takeawayEntrySessionId,
      pickupMode: pickupMode ?? this.pickupMode,
      pickupTime: pickupTime ?? this.pickupTime,
      contactFirstName: contactFirstName ?? this.contactFirstName,
      contactLastName: contactLastName ?? this.contactLastName,
      contactPhone: contactPhone ?? this.contactPhone,
      courierVisibility: courierVisibility ?? this.courierVisibility,
      lines: lines ?? this.lines,
      pricing: pricing ?? this.pricing,
      statusHistory: statusHistory ?? this.statusHistory,
      version: version ?? this.version,
      timestamps: timestamps ?? this.timestamps,
      customerNote: customerNote ?? this.customerNote,
      kitchenNote: kitchenNote ?? this.kitchenNote,
      deliveryAddressSnapshot:
          deliveryAddressSnapshot ?? this.deliveryAddressSnapshot,
      paymentMethodSnapshot:
          paymentMethodSnapshot ?? this.paymentMethodSnapshot,
      selectedBenefitType: selectedBenefitType ?? this.selectedBenefitType,
      boncukRedemption: boncukRedemption ?? this.boncukRedemption,
      catalogReward: catalogReward ?? this.catalogReward,
      campaign: campaign ?? this.campaign,
    );
  }
}
