import '../../../../core/errors/business_rule_violation.dart';
import '../../../../shared/models/currency.dart';
import '../../../../shared/models/money.dart';
import '../../../cart/domain/models/cart_item.dart';
import '../models/courier_visibility.dart';
import '../models/order.dart';
import '../models/order_channel.dart';
import '../models/order_id.dart';
import '../models/order_line.dart';
import '../models/order_line_modifier_selection.dart';
import '../models/order_number.dart';
import '../models/order_status.dart';
import '../models/order_timestamps.dart';
import '../pricing/price_calculator.dart';
import '../pricing/tax_policy.dart';
import '../pricing/tax_rate.dart';

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
  }) {
    if (cartItems.isEmpty) {
      throw const EmptyOrderViolation();
    }

    final lines = cartItems.map((item) => _mapLine(item, taxRate)).toList();
    final pricing = PriceCalculator.calculate(
      lines: lines,
      currency: Currency.tryLira,
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
    );
  }

  static OrderLine _mapLine(CartItem item, TaxRate taxRate) {
    // item.price and item.extraCostPerUnit are both already "per unit"
    // gross TRY amounts (see CartItem.unitPrice's own doc comment) —
    // folded together here, since OrderLine has no field shaped to carry
    // extraCostPerUnit separately and it has no name/identity of its own
    // to preserve as a modifier line.
    final unitPrice = Money.fromLegacyDoubleTry(item.price) +
        Money.fromLegacyDoubleTry(item.extraCostPerUnit);

    final modifierSelections = item.selectedModifiers
        .map(
          (modifier) => OrderLineModifierSelection(
            groupId: modifier.groupId,
            groupName: modifier.groupName,
            optionId: modifier.optionId,
            optionName: modifier.optionName,
            unitExtraPrice: Money.fromLegacyDoubleTry(modifier.extraPrice),
            // CartItem/SelectedModifier carry no per-selection quantity
            // today — every existing selection is implicitly quantity 1.
            quantity: 1,
          ),
        )
        .toList();

    // selectedProtein/selectedSauce/extraIngredients/removedIngredients
    // predate SelectedModifier and carry no individual price of their own
    // (only the single combined extraCostPerUnit folded into unitPrice
    // above) — preserved as free-text kitchen instructions instead of
    // invented modifier prices, mirroring exactly how
    // OrderItemSnapshot.fromCartItem already flattens the same fields.
    final kitchenNoteParts = <String>[
      if (item.selectedProtein.isNotEmpty) 'Protein: ${item.selectedProtein}',
      if (item.selectedSauce.isNotEmpty) 'Sos: ${item.selectedSauce}',
      for (final extra in item.extraIngredients) 'Ekstra: $extra',
      if (item.removedIngredients.isNotEmpty)
        'Çıkarılan: ${item.removedIngredients.join(", ")}',
    ];

    return OrderLine.create(
      productId: item.id,
      productName: item.name,
      modifiers: modifierSelections,
      quantity: item.quantity,
      unitPrice: unitPrice,
      taxRate: taxRate,
      kitchenNote: kitchenNoteParts.join(' | '),
      customerNote: item.note,
    );
  }
}
