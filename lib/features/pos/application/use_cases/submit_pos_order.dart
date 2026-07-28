import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../../orders/domain/discounts/discount.dart';
import '../../../orders/domain/identity/order_identity.dart';
import '../../../orders/domain/mappers/cart_to_order_mapper.dart';
import '../../../orders/domain/models/order.dart';
import '../../../orders/domain/models/order_actor.dart';
import '../../../orders/domain/models/order_status.dart';
import '../../data/pos_order_repository.dart';
import '../../domain/models/discount_snapshot.dart';
import '../../domain/models/pos_order_session.dart';

/// Freezes a [PosOrderSession] into a real [Order] and persists it.
///
/// **Duplicate-submission prevention lives in the controller, not here**
/// (deliberate placement — see `docs/decisions.md`): the controller's
/// [PosOrderSessionStatus] is already the single source of truth for "is a
/// submission currently in flight," so this use case stays a plain,
/// stateless orchestration step rather than tracking a second, potentially
/// disagreeing "in progress" flag of its own.
///
/// Steps (approved architecture decision, Phase 3 Sprint 3B):
/// 1. Reject an empty session ([EmptyOrderViolation]).
/// 2. Obtain a real identity via [OrderIdentityProvider] — never a
///    timestamp/random value/UUID invented here.
/// 3. Map the session to an [Order] via [CartToOrderMapper] (status
///    [OrderStatus.created], per-line/order-level notes and discounts
///    snapshotted).
/// 4. Transition `created -> pendingConfirmation` (the one valid next
///    state — see `OrderStatusTransitions`), actor [OrderActor.staff],
///    which appends the required [OrderAuditEntry] via `Order.transitionTo`
///    itself.
/// 5. Persist via [PosOrderRepository.submitOrder].
/// 6. Delete the session's draft — **only after** step 5 succeeds; a
///    failure at any earlier step leaves the draft intact so the cashier
///    can retry without having lost their in-progress order.
class SubmitPosOrder {
  SubmitPosOrder({
    required Clock clock,
    required OrderIdentityProvider identityProvider,
    required PosOrderRepository repository,
    required String restaurantId,
  })  : _clock = clock,
        _identityProvider = identityProvider,
        _repository = repository,
        _restaurantId = restaurantId;

  final Clock _clock;
  final OrderIdentityProvider _identityProvider;
  final PosOrderRepository _repository;
  final String _restaurantId;

  Future<Order> call(PosOrderSession session) async {
    if (session.lines.isEmpty) {
      throw const EmptyOrderViolation();
    }

    final orderId = await _identityProvider.nextOrderId();
    final orderNumber = await _identityProvider.nextOrderNumber();
    final now = _clock.now();

    final lineDiscounts = [
      for (final draft in session.lines)
        _activeLineDiscount(session.discounts, draft.id)?.discountAmount,
    ];
    final orderDiscountAmount =
        _activeOrderDiscount(session.discounts)?.discountAmount;

    var order = CartToOrderMapper.map(
      orderId: orderId,
      orderNumber: orderNumber,
      cartItems: [for (final draft in session.lines) draft.item],
      lineDiscounts: lineDiscounts,
      channel: session.channel,
      branchId: session.branchId,
      restaurantId: _restaurantId,
      tableId: session.tableId,
      tableSessionId: session.tableSessionId,
      orderLevelDiscount: orderDiscountAmount,
      serviceFee: session.fees,
      tip: session.tip,
      now: now,
      customerNote: session.customerNote,
      kitchenNote: session.kitchenNote,
    );

    order = order.transitionTo(
      OrderStatus.pendingConfirmation,
      actor: OrderActor.staff,
      at: now,
      // Unique within this order's own history (its first-ever
      // transition) — deliberately not routed through
      // OrderIdentityProvider, which is scoped to OrderId/OrderNumber
      // only (see its own doc comment), not audit-entry identity.
      auditEntryId: '${orderId.value}-transition-1',
    );

    final persisted = await _repository.submitOrder(order);
    await _repository.deleteDraft(session.sessionId);
    return persisted;
  }

  static DiscountSnapshot? _activeLineDiscount(
    List<DiscountSnapshot> discounts,
    String orderLineDraftId,
  ) {
    for (final discount in discounts) {
      if (discount.scope == DiscountScope.line &&
          discount.targetOrderLineId == orderLineDraftId) {
        return discount;
      }
    }
    return null;
  }

  static DiscountSnapshot? _activeOrderDiscount(
      List<DiscountSnapshot> discounts) {
    for (final discount in discounts) {
      if (discount.scope == DiscountScope.order) return discount;
    }
    return null;
  }
}
