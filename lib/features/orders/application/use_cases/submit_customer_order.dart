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
import '../../domain/models/order_status.dart';

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
        _branchId = branchId,
        _restaurantId = restaurantId;

  final Clock _clock;
  final OrderIdentityProvider _identityProvider;
  final CanonicalOrderRepository _repository;
  final String _branchId;
  final String _restaurantId;

  Future<Order> call({
    required List<CartItem> cartItems,
    required String? customerId,
    OrderChannel channel = OrderChannel.delivery,
    Money? deliveryFee,
    Money? orderLevelDiscount,
    String customerNote = '',
  }) async {
    if (cartItems.isEmpty) {
      throw const EmptyOrderViolation();
    }

    final orderId = await _identityProvider.nextOrderId();
    final orderNumber = await _identityProvider.nextOrderNumber();
    final now = _clock.now();

    var order = CartToOrderMapper.map(
      orderId: orderId,
      orderNumber: orderNumber,
      cartItems: cartItems,
      channel: channel,
      branchId: _branchId,
      restaurantId: _restaurantId,
      customerId: customerId,
      deliveryFee: deliveryFee,
      orderLevelDiscount: orderLevelDiscount,
      now: now,
      customerNote: customerNote,
    );

    order = order.transitionTo(
      OrderStatus.pendingConfirmation,
      actor: OrderActor.customer,
      at: now,
      auditEntryId: '${orderId.value}-transition-1',
    );

    return _repository.submitOrder(order);
  }
}
