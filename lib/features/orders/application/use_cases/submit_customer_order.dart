import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../../shared/models/money.dart';
import '../../../cart/domain/models/cart_item.dart';
import '../../data/canonical_order_repository.dart';
import '../../domain/identity/order_identity.dart';
import '../../domain/mappers/cart_to_order_mapper.dart';
import '../../domain/models/order.dart';
import '../../domain/models/order_actor.dart';
import '../../domain/models/order_channel.dart';
import '../../domain/models/order_id.dart';
import '../../domain/models/order_number.dart';
import '../../domain/models/order_status.dart';
import '../../domain/models/pickup_mode.dart';

/// Builds and persists a real, canonical [Order] from the customer-facing
/// cart/checkout flow — Sprint 9D (`docs/decisions.md` ADR-026). Mirrors
/// `SubmitPosOrder`'s exact shape/steps (same [OrderIdentityProvider],
/// same [CartToOrderMapper], same `created -> pendingConfirmation`
/// transition) so a customer-placed order and a staff-placed order are
/// genuinely the same kind of object going through the same lifecycle —
/// not two independently-evolving models that merely look similar.
///
/// [customerId] is the caller's responsibility to resolve (the checkout
/// screen passes `AuthSession.uid` for an authenticated session, `null`
/// for a guest — see `docs/decisions.md` ADR-026 Decision 5) — this class
/// never reads `authProvider` itself, keeping `features/orders` free of a
/// dependency on `features/auth`.
///
/// **Known interim limitation, not silently dropped**: the legacy
/// checkout screen collects several delivery-preference/scheduling fields
/// (ring bell, leave-at-door, contactless, courier-can-call, cutlery
/// preference, scheduled delivery time) that have no structured field on
/// the canonical [Order] — [call] folds their human-readable summary into
/// [customerNote] rather than losing them outright. Restoring them as
/// first-class, individually-queryable fields is separate, future
/// domain-model work.
///
/// [branchId]/[restaurantId] (constructor) are this use case's *default*
/// scope, resolved once at DI-wiring time (`submitCustomerOrderProvider`
/// currently wires the app's single seeded `'branch-1'`/`'restaurant-1'`
/// — there is still no restaurant/branch *selection* UI anywhere in the
/// customer app). [call]'s own `branchId`/`restaurantId` parameters
/// (Faz B, Gel Al architecture analysis) let a specific call override that
/// default with a real, resolved scope (e.g. a future takeaway QR token's
/// branch) without changing what every existing caller that omits them
/// gets — additive, not a breaking change to this class's constructor.
class SubmitCustomerOrder {
  SubmitCustomerOrder({
    required Clock clock,
    required OrderIdentityProvider identityProvider,
    required CanonicalOrderRepository repository,
    required String branchId,
    required String restaurantId,
  })  : _clock = clock,
        _identityProvider = identityProvider,
        _repository = repository,
        _defaultBranchId = branchId,
        _defaultRestaurantId = restaurantId;

  final Clock _clock;
  final OrderIdentityProvider _identityProvider;
  final CanonicalOrderRepository _repository;
  final String _defaultBranchId;
  final String _defaultRestaurantId;

  Future<Order> call({
    required List<CartItem> cartItems,
    required String? customerId,
    OrderChannel channel = OrderChannel.delivery,

    /// Overrides this use case's constructor-provided default scope for
    /// this one call — `null` (the default) keeps today's exact behavior.
    /// See this class's own doc comment.
    String? branchId,
    String? restaurantId,

    /// Table/session identifiers for a [OrderChannel.dineInQr] order —
    /// `null` for every other channel, mirroring `Order.tableId`/
    /// `tableSessionId`/`guestSessionId`'s own optionality. Threaded
    /// straight into [CartToOrderMapper.map], which already accepted these
    /// (Sprint 3A) — this use case just didn't expose them until the
    /// customer-facing dine-in checkout needed to (Masada Sipariş
    /// functional pass, 2026-08-08).
    String? tableId,
    String? tableSessionId,
    String? guestSessionId,

    /// The raw technical Firebase Auth uid that submitted a
    /// [OrderChannel.dineInQr] order — Phase 3.1. See [Order.guestAuthUid]
    /// for why this is threaded independently of [customerId].
    String? guestAuthUid,

    /// Server-generated snapshot from the table guest session that
    /// authorized this order — Faz R.1C.2. See [Order.reservationContextId]
    /// for the full identity/immutability contract; `null` for every
    /// non-reservation-table dine-in visit and every non-dineInQr channel.
    String? reservationContextId,

    /// Gel Al (takeaway) fields — Faz B. See [Order.takeawayEntrySessionId]/
    /// [Order.pickupMode]/[Order.pickupTime]/[Order.contactFirstName]/
    /// [Order.contactLastName]/[Order.contactPhone] for their exact
    /// semantics; `null` for every non-takeaway order.
    String? takeawayEntrySessionId,
    PickupMode? pickupMode,
    DateTime? pickupTime,
    String? contactFirstName,
    String? contactLastName,
    String? contactPhone,
    Money? deliveryFee,
    Money? orderLevelDiscount,
    String customerNote = '',

    /// A caller-supplied, pre-generated identity to reuse instead of
    /// minting a fresh one via [OrderIdentityProvider] — Faz C's minimal
    /// idempotency mechanism. A checkout screen that generates
    /// [orderId]/[orderNumber] once (e.g. in `initState`) and passes the
    /// same pair on every retry (a dropped connection, a resend after a
    /// timeout) makes that retry a `.set()` on the same document id,
    /// which `CanonicalOrderRepository.submitOrder` already treats as an
    /// idempotent overwrite rather than a second order. `null` (every
    /// existing caller) preserves today's "always mint a fresh id" default
    /// exactly.
    OrderId? orderId,
    OrderNumber? orderNumber,
  }) async {
    if (cartItems.isEmpty) {
      throw const EmptyOrderViolation();
    }

    final resolvedOrderId = orderId ?? await _identityProvider.nextOrderId();
    final resolvedOrderNumber =
        orderNumber ?? await _identityProvider.nextOrderNumber();
    final now = _clock.now();

    var order = CartToOrderMapper.map(
      orderId: resolvedOrderId,
      orderNumber: resolvedOrderNumber,
      cartItems: cartItems,
      channel: channel,
      branchId: branchId ?? _defaultBranchId,
      restaurantId: restaurantId ?? _defaultRestaurantId,
      customerId: customerId,
      tableId: tableId,
      tableSessionId: tableSessionId,
      guestSessionId: guestSessionId,
      guestAuthUid: guestAuthUid,
      reservationContextId: reservationContextId,
      takeawayEntrySessionId: takeawayEntrySessionId,
      pickupMode: pickupMode,
      pickupTime: pickupTime,
      contactFirstName: contactFirstName,
      contactLastName: contactLastName,
      contactPhone: contactPhone,
      deliveryFee: deliveryFee,
      orderLevelDiscount: orderLevelDiscount,
      now: now,
      customerNote: customerNote,
    );

    order = order.transitionTo(
      OrderStatus.pendingConfirmation,
      actor: OrderActor.customer,
      at: now,
      auditEntryId: '${resolvedOrderId.value}-transition-1',
    );

    return _repository.submitOrder(order);
  }
}
