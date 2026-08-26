import 'courier_visibility.dart';
import 'order.dart';
import 'order_audit_entry.dart';
import 'order_cancellation.dart';
import 'order_channel.dart';
import 'order_item_snapshot.dart';
import 'order_status.dart';
import 'order_timestamps.dart';
import 'pickup_mode.dart';

/// **LEGACY** — mixes canonical lifecycle fields with customer-app-UI-only
/// fields (delivery-instruction flags, review/rating fields, ...); see
/// [Order]'s own doc comment for the approved architecture decision
/// (Phase 3 Sprint 3A) keeping the two types separate, and Faz P.1
/// (`docs/decisions.md`) for why the new Paket Servis (delivery) domain
/// foundation — [Order.deliveryAddressSnapshot]/
/// [Order.paymentMethodSnapshot] — was added to [Order], not here. Not
/// migrated or replaced by this phase; that remains separate, future,
/// out-of-scope work.
class OrderModel {
  final String id;
  final String date;
  final double totalAmount;

  /// Legacy, localized display status (e.g. `'Teslim Edildi'`) the current
  /// order-history UI reads directly. Left untouched by this phase — see
  /// [lifecycleStatus] and `docs/order_lifecycle_architecture.md` for the
  /// canonical replacement this UI has not yet migrated to.
  final String status;

  // --- Sipariş Yaşam Döngüsü ve Güvenilirlik Temeli ---
  // (Order Lifecycle & Reliability Foundation — see
  // docs/order_lifecycle_architecture.md)

  /// Canonical order origin — see [OrderChannel].
  final OrderChannel channel;

  /// Canonical, channel-agnostic lifecycle state — see [OrderStatus] and
  /// [OrderStatusTransitions]. Not yet read by any UI in this phase.
  final OrderStatus lifecycleStatus;

  /// Frozen, point-in-time line items. Empty by default because no current
  /// call site constructs an order with real items yet — see
  /// [OrderItemSnapshot].
  final List<OrderItemSnapshot> items;

  /// Idempotency metadata a future backend uses to detect and collapse
  /// duplicate submissions of the same logical order. See
  /// `docs/order_lifecycle_architecture.md` §4 for intended backend
  /// behaviour; nothing in this codebase generates or checks these values
  /// yet.
  final String requestId;
  final String createdDeviceId;
  final String createdSessionId;

  /// When this order reached each tracked lifecycle stage. Nullable as a
  /// whole (not defaulted) because a `const` order literal cannot compute
  /// "now" for `created` at compile time — callers that care about timing
  /// construct one explicitly.
  final OrderTimestamps? timestamps;

  /// Structured cancellation metadata (reason/actor/timestamp), present
  /// only when the order has actually been cancelled. Coexists with the
  /// legacy [cancellationReason]/[cancellationDescription]/[cancelledAt]
  /// string fields below for the same reason [lifecycleStatus] coexists
  /// with [status] — see `docs/order_lifecycle_architecture.md`.
  final OrderCancellationInfo? cancellation;

  /// Append-only, in-memory record of changes made to this order. No
  /// persistence yet — see [OrderAuditEntry].
  final List<OrderAuditEntry> auditTrail;

  // --- Aktif Sipariş Takibi (Active Order Tracking) ---

  /// Estimated prep time (dine-in/takeaway) or delivery time (delivery),
  /// in minutes. Frozen at order creation from
  /// `RestaurantStatusModel`/`DeliveryZoneModel` — like [items], it must
  /// not drift if the restaurant's live estimate changes afterward.
  final int estimatedMinutes;

  /// Whether a courier's live delivery status may currently be shown to the
  /// customer — see [CourierVisibility] for the privacy rule this enforces.
  /// Only ever [CourierVisibility.visibleToCustomer] while
  /// [lifecycleStatus] is [OrderStatus.outForDelivery]; every other status
  /// resets it to [CourierVisibility.hidden].
  final CourierVisibility courierVisibility;

  /// The branch this order was placed against. The app only models a
  /// single real branch today (Abaküs Ortaköy, from the real menu import),
  /// so this defaults to it rather than requiring every call site to pass
  /// it — additive groundwork for the multi-branch case, not a claim that
  /// branch selection exists yet.
  final String branchName;

  /// Delivery fee charged for this order, frozen at checkout time. `0` for
  /// non-delivery channels or a free-delivery coupon.
  final double deliveryFeeAmount;

  /// Order-level discount applied at checkout (e.g. a coupon), frozen at
  /// checkout time. Distinct from any future per-line
  /// [OrderItemSnapshot.discountAmount].
  final double discountAmount;

  /// Frozen, display-ready delivery address text for [OrderChannel.delivery]
  /// orders (e.g. `'Ev - Kadıköy, ...'`). Empty for other channels.
  final String deliveryAddressText;

  /// Table identity for a [OrderChannel.dineInQr]/[OrderChannel.dineInStaff]
  /// order (Masada Sipariş functional pass, 2026-08-08) — `null`/empty for
  /// every other channel. [tableId] mirrors `Order.tableId`; [tableName] is
  /// the display-ready name (`'Masa 12'`) frozen at submission time, the
  /// same "snapshot, don't reference the live catalog" reasoning
  /// [branchName] already follows — `ActiveOrderScreen` should never need
  /// to re-resolve a `RestaurantTable` just to show its own order.
  final String? tableId;
  final String? tableName;

  /// Gel Al (takeaway) pickup/contact data (Faz B, Gel Al architecture
  /// analysis) — mirrors `Order.pickupMode`/`pickupTime`/`contactFirstName`/
  /// `contactLastName`/`contactPhone` exactly, threaded straight through
  /// [fromCanonicalOrder] the same way [tableId] already is. `null`/empty
  /// for every non-takeaway order. Carried here (not just left on the
  /// canonical [Order]) so this projection doesn't lose them either — the
  /// same "don't let a projection silently drop a real field" reasoning
  /// [tableId]/[tableName] already follow, and groundwork for POS/KDS
  /// surfaces that may read through this model later (no such UI exists
  /// yet — out of this phase's scope).
  final PickupMode? pickupMode;
  final DateTime? pickupTime;
  final String? contactFirstName;
  final String? contactLastName;
  final String? contactPhone;

  /// Server-Authoritative Campaign Engine P8-C (2026-08-25) — the frozen
  /// campaign-redemption summary for order-history/detail display, sourced
  /// straight from `Order.campaign` (never re-derived or re-resolved from a
  /// live campaign). `null`/`0` for every order that didn't apply a
  /// campaign, including every pre-P8-C order — a purely additive field,
  /// same backward-compatibility contract as [tableId]/[pickupMode] above.
  final String? campaignTitle;
  final int? campaignDiscountMinorUnits;

  /// Customer-side closure audit fix — the same "frozen snapshot, never a
  /// live re-lookup" contract [campaignTitle]/[campaignDiscountMinorUnits]
  /// already have, extended to the other two benefit families so historical
  /// Order Detail can show what a customer actually redeemed on a past
  /// order (previously silently dropped by this projection even though the
  /// backend snapshot always carried it — `Order.catalogReward`/
  /// `Order.boncukRedemption`). `null`/`0` for every order that didn't use
  /// that benefit.
  final String? catalogRewardTitle;
  final int? catalogRewardCoveredValueMinorUnits;
  final int? boncukRedemptionBoncukUsed;
  final int? boncukRedemptionValueMinorUnits;

  // --- Mevcut (legacy) alanlar: bu faz tarafından değiştirilmedi ---

  // FEATURE 28 Uyumlu Alanlar
  final String orderNote;
  final String serviceMaterialsPreference;
  final bool ringBell;
  final bool leaveAtDoor;
  final bool contactlessDelivery;
  final bool courierCanCall;
  final String leaveAtDoorLocation;
  final String customDeliveryInstruction;

  // FEATURE 30 Uyumlu Alanlar
  final String deliveryTimingType;
  final String scheduledDeliveryDateTime;

  // FEATURE 31 Uyumlu Alanlar
  final String? cancellationReason;
  final String? cancellationDescription;
  final String? cancelledAt;

  // FEATURE 32 Uyumlu Alanlar
  final int? overallRating;
  final int? tasteRating;
  final int? packagingRating;
  final int? deliveryRating;
  final String? reviewComment;
  final String? reviewedAt;

  final int? courierRating;
  final bool? courierWasPolite;
  final bool? courierWasOnTime;
  final bool? courierCommunicationWasGood;
  final bool? packageWasHandledCarefully;
  final String? courierReviewComment;

  const OrderModel({
    required this.id,
    required this.date,
    required this.totalAmount,
    required this.status,
    this.channel = OrderChannel.delivery,
    this.lifecycleStatus = OrderStatus.created,
    this.items = const [],
    this.requestId = '',
    this.createdDeviceId = '',
    this.createdSessionId = '',
    this.timestamps,
    this.cancellation,
    this.auditTrail = const [],
    this.estimatedMinutes = 30,
    this.courierVisibility = CourierVisibility.hidden,
    this.branchName = 'Abaküs Ortaköy',
    this.deliveryFeeAmount = 0.0,
    this.discountAmount = 0.0,
    this.deliveryAddressText = '',
    this.tableId,
    this.tableName,
    this.pickupMode,
    this.pickupTime,
    this.contactFirstName,
    this.contactLastName,
    this.contactPhone,
    this.campaignTitle,
    this.campaignDiscountMinorUnits,
    this.catalogRewardTitle,
    this.catalogRewardCoveredValueMinorUnits,
    this.boncukRedemptionBoncukUsed,
    this.boncukRedemptionValueMinorUnits,
    this.orderNote = '',
    this.serviceMaterialsPreference = '',
    this.ringBell = true,
    this.leaveAtDoor = false,
    this.contactlessDelivery = false,
    this.courierCanCall = true,
    this.leaveAtDoorLocation = '',
    this.customDeliveryInstruction = '',
    this.deliveryTimingType = 'immediate',
    this.scheduledDeliveryDateTime = '',
    this.cancellationReason,
    this.cancellationDescription,
    this.cancelledAt,
    this.overallRating,
    this.tasteRating,
    this.packagingRating,
    this.deliveryRating,
    this.reviewComment,
    this.reviewedAt,
    this.courierRating,
    this.courierWasPolite,
    this.courierWasOnTime,
    this.courierCommunicationWasGood,
    this.packageWasHandledCarefully,
    this.courierReviewComment,
  });

  /// Projects a canonical [Order] (`order.dart`) into the shape this
  /// legacy, UI-facing model's screens (`orders_screen.dart`,
  /// `order_detail_screen.dart`, `active_order_screen.dart`) already know
  /// how to render — Sprint 9D (`docs/decisions.md` ADR-026). As of this
  /// sprint, [Order] is the one authoritative, created/persisted/
  /// lifecycle-tracked aggregate for both POS and customer checkout;
  /// [OrderModel] is a **read/presentation projection** of it, not a
  /// second source of truth.
  ///
  /// [status] is derived via [OrderStatusLegacyLabel.forStatus] (the
  /// bridge already built for exactly this purpose). Money fields convert
  /// [Order.pricing]'s [Money] values back to `double` — the mirror image
  /// of `Money.fromLegacyDoubleTry`'s boundary, used only here, at the
  /// canonical-to-legacy-projection edge.
  ///
  /// **Known, explicitly-reported limitation**: the ~25 customer-app-UI-only
  /// fields this model carries (delivery-preference toggles, scheduling,
  /// review/rating surveys) have no structured equivalent on [Order] —
  /// [SubmitCustomerOrder] folds their checkout-time values into
  /// [Order.customerNote] as readable text instead of losing them, but
  /// this projection cannot losslessly reconstruct the individual
  /// booleans/strings from that text, so they default to this
  /// constructor's normal defaults here. The order note itself (surfaced
  /// via [orderNote]) still carries the full information for a human to
  /// read; only the *structured, individually-toggleable* display is
  /// affected. Restoring first-class structured fields is separate,
  /// future domain-model work, not silently dropped functionality.
  ///
  /// [tableName] can't be derived here — [Order] only carries [tableId]
  /// (an id, not a display string), and this `orders`-domain model must
  /// not depend on `features/qr`/`features/restaurant` to resolve one
  /// (`CLAUDE.md` §3 layering). The caller that actually has a
  /// `RestaurantTable`/`ActiveTableContext` in hand at submission time
  /// (`DineInCheckoutScreen`) is expected to chain `.copyWith(tableName:
  /// ...)` immediately after this factory, the same "caller supplies
  /// context this layer can't reach" pattern already used elsewhere in
  /// this projection.
  factory OrderModel.fromCanonicalOrder(Order order) {
    final created = order.timestamps.created;
    return OrderModel(
      id: order.id.value,
      date: '${created.day.toString().padLeft(2, '0')}.'
          '${created.month.toString().padLeft(2, '0')}.'
          '${created.year}',
      totalAmount: order.pricing.grandTotal.minorUnits /
          order.pricing.grandTotal.currency.minorUnitsPerWhole,
      status: OrderStatusLegacyLabel.forStatus(order.status),
      channel: order.channel,
      lifecycleStatus: order.status,
      items: [
        for (final line in order.lines)
          OrderItemSnapshot(
            productId: line.productId,
            productName: line.productName,
            quantity: line.quantity,
            unitPrice: line.unitPrice.minorUnits /
                line.unitPrice.currency.minorUnitsPerWhole,
            notes: line.kitchenNote,
          ),
      ],
      timestamps: order.timestamps,
      deliveryFeeAmount: order.pricing.deliveryFee.minorUnits /
          order.pricing.deliveryFee.currency.minorUnitsPerWhole,
      discountAmount: order.pricing.discount.minorUnits /
          order.pricing.discount.currency.minorUnitsPerWhole,
      tableId: order.tableId,
      pickupMode: order.pickupMode,
      pickupTime: order.pickupTime,
      contactFirstName: order.contactFirstName,
      contactLastName: order.contactLastName,
      contactPhone: order.contactPhone,
      campaignTitle: order.campaign?.title,
      campaignDiscountMinorUnits: order.campaign?.discountMinorUnits,
      catalogRewardTitle: order.catalogReward?.title,
      catalogRewardCoveredValueMinorUnits:
          order.catalogReward?.coveredValueMinorUnits,
      boncukRedemptionBoncukUsed: order.boncukRedemption?.boncukUsed,
      boncukRedemptionValueMinorUnits: order.boncukRedemption?.valueMinorUnits,
      orderNote: order.customerNote,
    );
  }

  OrderModel copyWith({
    String? id,
    String? date,
    double? totalAmount,
    String? status,
    OrderChannel? channel,
    OrderStatus? lifecycleStatus,
    List<OrderItemSnapshot>? items,
    String? requestId,
    String? createdDeviceId,
    String? createdSessionId,
    OrderTimestamps? timestamps,
    OrderCancellationInfo? cancellation,
    List<OrderAuditEntry>? auditTrail,
    int? estimatedMinutes,
    CourierVisibility? courierVisibility,
    String? branchName,
    double? deliveryFeeAmount,
    double? discountAmount,
    String? deliveryAddressText,
    String? tableId,
    String? tableName,
    PickupMode? pickupMode,
    DateTime? pickupTime,
    String? contactFirstName,
    String? contactLastName,
    String? contactPhone,
    String? campaignTitle,
    int? campaignDiscountMinorUnits,
    String? catalogRewardTitle,
    int? catalogRewardCoveredValueMinorUnits,
    int? boncukRedemptionBoncukUsed,
    int? boncukRedemptionValueMinorUnits,
    String? orderNote,
    String? serviceMaterialsPreference,
    bool? ringBell,
    bool? leaveAtDoor,
    bool? contactlessDelivery,
    bool? courierCanCall,
    String? leaveAtDoorLocation,
    String? customDeliveryInstruction,
    String? deliveryTimingType,
    String? scheduledDeliveryDateTime,
    String? cancellationReason,
    String? cancellationDescription,
    String? cancelledAt,
    int? overallRating,
    int? tasteRating,
    int? packagingRating,
    int? deliveryRating,
    String? reviewComment,
    String? reviewedAt,
    int? courierRating,
    bool? courierWasPolite,
    bool? courierWasOnTime,
    bool? courierCommunicationWasGood,
    bool? packageWasHandledCarefully,
    String? courierReviewComment,
  }) {
    return OrderModel(
      id: id ?? this.id,
      date: date ?? this.date,
      totalAmount: totalAmount ?? this.totalAmount,
      status: status ?? this.status,
      channel: channel ?? this.channel,
      lifecycleStatus: lifecycleStatus ?? this.lifecycleStatus,
      items: items ?? this.items,
      requestId: requestId ?? this.requestId,
      createdDeviceId: createdDeviceId ?? this.createdDeviceId,
      createdSessionId: createdSessionId ?? this.createdSessionId,
      timestamps: timestamps ?? this.timestamps,
      cancellation: cancellation ?? this.cancellation,
      auditTrail: auditTrail ?? this.auditTrail,
      estimatedMinutes: estimatedMinutes ?? this.estimatedMinutes,
      courierVisibility: courierVisibility ?? this.courierVisibility,
      branchName: branchName ?? this.branchName,
      deliveryFeeAmount: deliveryFeeAmount ?? this.deliveryFeeAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      deliveryAddressText: deliveryAddressText ?? this.deliveryAddressText,
      tableId: tableId ?? this.tableId,
      tableName: tableName ?? this.tableName,
      pickupMode: pickupMode ?? this.pickupMode,
      pickupTime: pickupTime ?? this.pickupTime,
      contactFirstName: contactFirstName ?? this.contactFirstName,
      contactLastName: contactLastName ?? this.contactLastName,
      contactPhone: contactPhone ?? this.contactPhone,
      campaignTitle: campaignTitle ?? this.campaignTitle,
      campaignDiscountMinorUnits:
          campaignDiscountMinorUnits ?? this.campaignDiscountMinorUnits,
      catalogRewardTitle: catalogRewardTitle ?? this.catalogRewardTitle,
      catalogRewardCoveredValueMinorUnits:
          catalogRewardCoveredValueMinorUnits ??
              this.catalogRewardCoveredValueMinorUnits,
      boncukRedemptionBoncukUsed:
          boncukRedemptionBoncukUsed ?? this.boncukRedemptionBoncukUsed,
      boncukRedemptionValueMinorUnits: boncukRedemptionValueMinorUnits ??
          this.boncukRedemptionValueMinorUnits,
      orderNote: orderNote ?? this.orderNote,
      serviceMaterialsPreference:
          serviceMaterialsPreference ?? this.serviceMaterialsPreference,
      ringBell: ringBell ?? this.ringBell,
      leaveAtDoor: leaveAtDoor ?? this.leaveAtDoor,
      contactlessDelivery: contactlessDelivery ?? this.contactlessDelivery,
      courierCanCall: courierCanCall ?? this.courierCanCall,
      leaveAtDoorLocation: leaveAtDoorLocation ?? this.leaveAtDoorLocation,
      customDeliveryInstruction:
          customDeliveryInstruction ?? this.customDeliveryInstruction,
      deliveryTimingType: deliveryTimingType ?? this.deliveryTimingType,
      scheduledDeliveryDateTime:
          scheduledDeliveryDateTime ?? this.scheduledDeliveryDateTime,
      cancellationReason: cancellationReason ?? this.cancellationReason,
      cancellationDescription:
          cancellationDescription ?? this.cancellationDescription,
      cancelledAt: cancelledAt ?? this.cancelledAt,
      overallRating: overallRating ?? this.overallRating,
      tasteRating: tasteRating ?? this.tasteRating,
      packagingRating: packagingRating ?? this.packagingRating,
      deliveryRating: deliveryRating ?? this.deliveryRating,
      reviewComment: reviewComment ?? this.reviewComment,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      courierRating: courierRating ?? this.courierRating,
      courierWasPolite: courierWasPolite ?? this.courierWasPolite,
      courierWasOnTime: courierWasOnTime ?? this.courierWasOnTime,
      courierCommunicationWasGood:
          courierCommunicationWasGood ?? this.courierCommunicationWasGood,
      packageWasHandledCarefully:
          packageWasHandledCarefully ?? this.packageWasHandledCarefully,
      courierReviewComment: courierReviewComment ?? this.courierReviewComment,
    );
  }
}
