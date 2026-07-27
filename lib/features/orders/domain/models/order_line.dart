import '../../../../core/errors/business_rule_violation.dart';
import '../../../../shared/models/money.dart';
import '../pricing/tax_rate.dart';
import '../pricing/tax_snapshot.dart';
import 'order_line_modifier_selection.dart';

/// One frozen, priced line on an [Order] — this sprint's replacement for
/// `OrderItemSnapshot`'s role within the new `Order` aggregate (see
/// `docs/decisions.md` for why the new aggregate stays separate from the
/// legacy `OrderModel`/`OrderItemSnapshot` pair this sprint).
///
/// Every field is computed once, at construction, from [unitPrice],
/// [modifiers], [quantity], [lineDiscount], and [taxRate] — never
/// independently supplied — so a line can't be constructed in an
/// internally-inconsistent state (e.g. a [lineTotal] that doesn't match
/// [unitPrice] × [quantity] plus modifiers minus discount).
class OrderLine {
  const OrderLine._({
    required this.productId,
    required this.productName,
    required this.modifiers,
    required this.quantity,
    required this.unitPrice,
    required this.modifierTotal,
    required this.lineSubtotal,
    required this.lineDiscount,
    required this.lineTotal,
    required this.tax,
    required this.kitchenNote,
    required this.customerNote,
  });

  /// Builds a line, computing [modifierTotal]/[lineSubtotal]/[lineTotal]/
  /// [tax] deterministically from the given inputs.
  ///
  /// [unitPrice] and every [OrderLineModifierSelection.unitExtraPrice] are
  /// gross (VAT-inclusive) — [taxRate] is only ever used to *extract* VAT
  /// from the resulting [lineTotal], never to add VAT on top (see
  /// `TaxRate`'s own doc comment).
  ///
  /// [lineTotal]'s VAT is extracted from the line's actual charged amount
  /// (post [lineDiscount]) — a line-level discount is treated as reducing
  /// what was actually sold, so it's reflected in [tax]. This is distinct
  /// from an *order*-level discount, which does not feed back into any
  /// line's [tax] (see `PriceBreakdown`'s doc comment) — the two are
  /// different events with different, separately-decided tax treatment.
  ///
  /// Throws [NonPositiveQuantityViolation] if [quantity] isn't positive,
  /// [NegativeAmountViolation] if [lineDiscount] is negative, or
  /// [NegativeTotalViolation] if the resulting [lineTotal] would be
  /// negative (a discount larger than the line's own subtotal).
  factory OrderLine.create({
    required String productId,
    required String productName,
    List<OrderLineModifierSelection> modifiers = const [],
    required int quantity,
    required Money unitPrice,
    Money? lineDiscount,
    required TaxRate taxRate,
    String kitchenNote = '',
    String customerNote = '',
  }) {
    if (quantity <= 0) {
      throw NonPositiveQuantityViolation(
        context: 'OrderLine.quantity',
        quantity: quantity,
      );
    }
    final discount = lineDiscount ?? Money.zero(unitPrice.currency);
    if (discount.isNegative) {
      throw NegativeAmountViolation(
        context: 'OrderLine.lineDiscount',
        minorUnits: discount.minorUnits,
        currencyCode: discount.currency.isoCode,
      );
    }

    final modifierTotal = modifiers.fold<Money>(
      Money.zero(unitPrice.currency),
      (sum, modifier) => sum + modifier.totalExtraPrice,
    );
    final lineSubtotal = (unitPrice + modifierTotal) * quantity;
    final lineTotal = lineSubtotal - discount;
    if (lineTotal.isNegative) {
      throw NegativeTotalViolation(
        minorUnits: lineTotal.minorUnits,
        currencyCode: lineTotal.currency.isoCode,
      );
    }

    return OrderLine._(
      productId: productId,
      productName: productName,
      modifiers: List.unmodifiable(modifiers),
      quantity: quantity,
      unitPrice: unitPrice,
      modifierTotal: modifierTotal,
      lineSubtotal: lineSubtotal,
      lineDiscount: discount,
      lineTotal: lineTotal,
      tax: TaxSnapshot.fromGrossAmount(lineTotal, taxRate),
      kitchenNote: kitchenNote,
      customerNote: customerNote,
    );
  }

  /// Frozen product identity (see `docs/business_rules.md` BR-ORDER-002 —
  /// a later menu/price change must never retroactively alter an existing
  /// line).
  final String productId;
  final String productName;

  final List<OrderLineModifierSelection> modifiers;
  final int quantity;

  /// Gross (VAT-inclusive) price for one unit of the product, before
  /// modifiers.
  final Money unitPrice;

  /// Gross sum of every modifier's [OrderLineModifierSelection
  /// .totalExtraPrice].
  final Money modifierTotal;

  /// `(unitPrice + modifierTotal) * quantity` — gross, before
  /// [lineDiscount].
  final Money lineSubtotal;

  /// A line-level discount (zero if none).
  final Money lineDiscount;

  /// `lineSubtotal - lineDiscount` — the gross amount actually charged for
  /// this line, and the amount [tax] is extracted from.
  final Money lineTotal;

  /// VAT breakdown for [lineTotal], frozen at line-creation time — see
  /// `TaxPolicy`.
  final TaxSnapshot tax;

  /// Free-text instruction for the kitchen (e.g. "az baharatlı").
  final String kitchenNote;

  /// Free-text note from the customer, distinct from [kitchenNote] — new
  /// capability this sprint adds; neither `CartItem` nor
  /// `OrderItemSnapshot` split these today (both have a single `note`).
  final String customerNote;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is OrderLine &&
            other.productId == productId &&
            other.productName == productName &&
            _listEquals(other.modifiers, modifiers) &&
            other.quantity == quantity &&
            other.unitPrice == unitPrice &&
            other.lineDiscount == lineDiscount &&
            other.lineTotal == lineTotal &&
            other.tax == tax &&
            other.kitchenNote == kitchenNote &&
            other.customerNote == customerNote);
  }

  @override
  int get hashCode => Object.hash(
        productId,
        productName,
        quantity,
        unitPrice,
        lineDiscount,
        lineTotal,
        tax,
        kitchenNote,
        customerNote,
      );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
