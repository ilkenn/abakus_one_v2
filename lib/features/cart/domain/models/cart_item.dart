import '../../../menu/domain/models/selected_modifier.dart';
import '../../../orders/domain/models/order_channel.dart';

/// A line in the customer's cart.
///
/// [selectedModifiers] is the generic, product-agnostic way a cart item
/// carries its chosen options (protein, sauce, extras, Bowl Builder
/// ingredients, ...) — see `SelectedModifier`. [selectedProtein]/
/// [selectedSauce]/[removedIngredients]/[extraIngredients] are the older,
/// bowl-specific fields kept only so the existing checkout/cart display
/// logic for previously-added items keeps working; new call sites
/// (redesigned Product Detail, Bowl Builder) populate [selectedModifiers]
/// instead. See `docs/menu_experience_architecture.md`.
class CartItem {
  final String id;
  final String name;
  final String desc;
  final double price;
  final int quantity;

  final String selectedProtein;
  final String selectedSauce;
  final List<String> removedIngredients;
  final List<String> extraIngredients;
  final double extraCostPerUnit;

  final List<SelectedModifier> selectedModifiers;
  final String note;

  /// Precomputed uniqueness key distinguishing this exact configuration
  /// from other quantities/customizations of the same product. Built by
  /// whoever constructs the item (see `CartNotifier.addToCart`) rather than
  /// derived here, so cart line matching stays a single, explicit, testable
  /// rule instead of implicit equality.
  final String customizationsKey;

  /// The channel [price]/[selectedModifiers] were resolved for at
  /// add-to-cart time (Faz C, Gel Al) — `null` means "resolved without
  /// channel awareness," the unchanged behavior for every cart item added
  /// before this field existed. Exists so a channel switch (delivery/
  /// dine-in ↔ takeaway) with items already in the cart can be detected
  /// and never silently priced under the wrong channel — see
  /// `CartScreen`'s channel-mismatch guard, the single place this field is
  /// actually read.
  final OrderChannel? pricedForChannel;

  const CartItem({
    required this.id,
    required this.name,
    required this.desc,
    required this.price,
    required this.quantity,
    this.selectedProtein = '',
    this.selectedSauce = '',
    this.removedIngredients = const [],
    this.extraIngredients = const [],
    this.extraCostPerUnit = 0.0,
    this.selectedModifiers = const [],
    this.note = '',
    this.customizationsKey = '',
    this.pricedForChannel,
  });

  /// Sum of this item's [extraCostPerUnit] and every selected modifier's
  /// extra price, added on top of [price].
  double get unitPrice =>
      price +
      extraCostPerUnit +
      selectedModifiers.fold(0.0, (sum, m) => sum + m.extraPrice);

  double get totalRowPrice => unitPrice * quantity;

  CartItem copyWith({
    String? id,
    String? name,
    String? desc,
    double? price,
    int? quantity,
    String? selectedProtein,
    String? selectedSauce,
    List<String>? removedIngredients,
    List<String>? extraIngredients,
    double? extraCostPerUnit,
    List<SelectedModifier>? selectedModifiers,
    String? note,
    String? customizationsKey,
    OrderChannel? pricedForChannel,
  }) {
    return CartItem(
      id: id ?? this.id,
      name: name ?? this.name,
      desc: desc ?? this.desc,
      price: price ?? this.price,
      quantity: quantity ?? this.quantity,
      selectedProtein: selectedProtein ?? this.selectedProtein,
      selectedSauce: selectedSauce ?? this.selectedSauce,
      removedIngredients: removedIngredients ?? this.removedIngredients,
      extraIngredients: extraIngredients ?? this.extraIngredients,
      extraCostPerUnit: extraCostPerUnit ?? this.extraCostPerUnit,
      selectedModifiers: selectedModifiers ?? this.selectedModifiers,
      note: note ?? this.note,
      customizationsKey: customizationsKey ?? this.customizationsKey,
      pricedForChannel: pricedForChannel ?? this.pricedForChannel,
    );
  }
}
