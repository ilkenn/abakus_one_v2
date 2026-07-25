import '../../../cart/domain/models/cart_item.dart';

/// An immutable, point-in-time record of one ordered line item.
///
/// Deliberately not the same type as the cart's line-item model
/// (`CartItem`): a cart line is live and tied to a product id so it can
/// keep reflecting menu/price changes until checkout. A
/// snapshot is the opposite — once an order is placed, its snapshot must
/// never change even if the underlying product, its price, or its
/// modifiers change or are deleted later. Freezing `productName` and
/// `modifierDescriptions` as plain text (rather than references) is what
/// makes that guarantee possible — see [OrderItemSnapshot.fromCartItem].
class OrderItemSnapshot {
  final String productId;
  final String productName;
  final List<String> modifierDescriptions;
  final int quantity;
  final double unitPrice;
  final double taxAmount;
  final double discountAmount;
  final String notes;

  const OrderItemSnapshot({
    required this.productId,
    required this.productName,
    this.modifierDescriptions = const [],
    required this.quantity,
    required this.unitPrice,
    this.taxAmount = 0.0,
    this.discountAmount = 0.0,
    this.notes = '',
  });

  /// Freezes one live [CartItem] into an immutable snapshot at checkout
  /// time. Every customization the cart line carries is preserved as plain
  /// text: [CartItem.selectedModifiers] (covers Product Detail modifiers and
  /// every Bowl Builder selection alike — both already flow through the
  /// same generic `SelectedModifier` shape), the legacy
  /// [CartItem.selectedProtein]/[CartItem.selectedSauce]/
  /// [CartItem.extraIngredients]/[CartItem.removedIngredients] fields kept
  /// for older cart lines, and [CartItem.note]. [CartItem.unitPrice]
  /// (base price + every modifier's extra price) becomes [unitPrice]
  /// directly — pricing is computed once, by the cart, and never
  /// recalculated here.
  factory OrderItemSnapshot.fromCartItem(CartItem item) {
    final modifierDescriptions = <String>[
      if (item.selectedProtein.isNotEmpty) 'Protein: ${item.selectedProtein}',
      if (item.selectedSauce.isNotEmpty) 'Sos: ${item.selectedSauce}',
      for (final modifier in item.selectedModifiers)
        '${modifier.groupName}: ${modifier.optionName}',
      for (final extra in item.extraIngredients) 'Ekstra: $extra',
      if (item.removedIngredients.isNotEmpty)
        'Çıkarılan: ${item.removedIngredients.join(", ")}',
    ];

    return OrderItemSnapshot(
      productId: item.id,
      productName: item.name,
      modifierDescriptions: modifierDescriptions,
      quantity: item.quantity,
      unitPrice: item.unitPrice,
      notes: item.note,
    );
  }

  /// Total for this line: unit price × quantity, plus tax, minus discount.
  double get lineTotal => (unitPrice * quantity) + taxAmount - discountAmount;

  OrderItemSnapshot copyWith({
    String? productId,
    String? productName,
    List<String>? modifierDescriptions,
    int? quantity,
    double? unitPrice,
    double? taxAmount,
    double? discountAmount,
    String? notes,
  }) {
    return OrderItemSnapshot(
      productId: productId ?? this.productId,
      productName: productName ?? this.productName,
      modifierDescriptions: modifierDescriptions ?? this.modifierDescriptions,
      quantity: quantity ?? this.quantity,
      unitPrice: unitPrice ?? this.unitPrice,
      taxAmount: taxAmount ?? this.taxAmount,
      discountAmount: discountAmount ?? this.discountAmount,
      notes: notes ?? this.notes,
    );
  }
}
