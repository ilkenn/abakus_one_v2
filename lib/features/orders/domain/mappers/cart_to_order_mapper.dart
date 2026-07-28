import '../../../../core/errors/business_rule_violation.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../cart/domain/models/cart_item.dart';
import '../models/courier_visibility.dart';
import '../models/order.dart';
import '../models/order_channel.dart';
import '../models/order_id.dart';
import '../models/order_number.dart';
import '../models/order_status.dart';
import '../models/order_timestamps.dart';
import '../pricing/price_calculator.dart';
import '../pricing/tax_policy.dart';
import '../pricing/tax_rate.dart';
import 'cart_line_mapper.dart';

/// Builds a new [Order] from the customer's live cart at checkout time —
/// the cart-to-order boundary. [Order] never depends on UI or Riverpod;
/// this mapper is the one place a (Flutter-free) `List<CartItem>` becomes
/// an immutable, frozen [Order].
///
/// Every price/modifier value is snapshotted here: [CartItem.price]/
/// [CartItem.selectedModifiers] are read once, converted to [Money], and
/// never referenced again — an [Order] built by this mapper has no
/// residual link back to the live cart or catalog (see `OrderLine`'s own
/// doc comment on why each field is computed once at construction).
/// Per-line snapshotting itself is [CartLineMapper]'s job, shared with
/// `CalculatePosOrderTotals`'s preview-only path — not duplicated here.
abstract final class CartToOrderMapper {
  CartToOrderMapper._();

  /// Throws [EmptyOrderViolation] if [cartItems] is empty. Every other
  /// validation ([OrderLine.create]'s non-negative/positive-quantity
  /// checks, [PriceCalculator.calculate]'s negative-total check) is
  /// inherited from the types this method composes, not re-implemented
  /// here.
  static Order map({
    required OrderId orderId,
    required OrderNumber orderNumber,
    required List<CartItem> cartItems,
    required OrderChannel channel,
    required String branchId,
    required String restaurantId,
    String? customerId,
    String? tableId,
    String? tableSessionId,
    String? guestSessionId,
    TaxRate taxRate = TaxPolicy.defaultRate,
    Money? orderLevelDiscount,
    Money? serviceFee,
    Money? deliveryFee,
    Money? packagingFee,
    Money? tip,
    required DateTime now,
    String customerNote = '',
    String kitchenNote = '',
  }) {
    if (cartItems.isEmpty) {
      throw const EmptyOrderViolation();
    }

    final lines = cartItems
        .map((item) => CartLineMapper.mapLine(item, taxRate))
        .toList();
    final pricing = PriceCalculator.calculate(
      lines: lines,
      currency: Currency.accountingCurrency,
      discount: orderLevelDiscount,
      serviceFee: serviceFee,
      deliveryFee: deliveryFee,
      packagingFee: packagingFee,
      tip: tip,
    );

    return Order(
      id: orderId,
      orderNumber: orderNumber,
      status: OrderStatus.created,
      channel: channel,
      branchId: branchId,
      restaurantId: restaurantId,
      customerId: customerId,
      tableId: tableId,
      tableSessionId: tableSessionId,
      guestSessionId: guestSessionId,
      courierVisibility: CourierVisibility.hidden,
      lines: lines,
      pricing: pricing,
      statusHistory: const [],
      version: 1,
      timestamps: OrderTimestamps(created: now),
      customerNote: customerNote,
      kitchenNote: kitchenNote,
    );
  }
}
