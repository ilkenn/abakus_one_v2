import '../../../../shared/models/money.dart';
import '../../../cart/domain/models/cart_item.dart';
import '../models/order_line.dart';
import '../models/order_line_modifier_selection.dart';
import '../pricing/tax_rate.dart';

/// Converts one live [CartItem] into a frozen [OrderLine] — the single
/// piece of line-snapshot/modifier-mapping logic both [CartToOrderMapper]
/// (a real order, needs an [OrderId]/[OrderNumber]) and
/// `CalculatePosOrderTotals` (a live pricing preview, needs neither) share.
/// Extracted specifically so a POS live totals preview never has to invent
/// a fake order identity just to compute a [PriceBreakdown] — see Phase 3
/// Sprint 3B's architecture decision on this.
abstract final class CartLineMapper {
  CartLineMapper._();

  static OrderLine mapLine(
    CartItem item,
    TaxRate taxRate, {
    Money? lineDiscount,
  }) {
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
      lineDiscount: lineDiscount,
      taxRate: taxRate,
      kitchenNote: kitchenNoteParts.join(' | '),
      customerNote: item.note,
    );
  }
}
