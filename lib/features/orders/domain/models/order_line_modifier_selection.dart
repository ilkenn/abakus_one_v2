import '../../../../shared/models/money.dart';

/// One frozen, priced modifier selection on an [OrderLine].
///
/// Deliberately flat and self-contained (`groupName`/`optionName` as text,
/// not just ids) — the same "snapshot, don't reference" principle
/// `SelectedModifier`/`OrderItemSnapshot` already follow.
///
/// [quantity] is new capability neither `ModifierGroup`/`ModifierOption`
/// nor the existing `SelectedModifier` support today (a customer picking
/// "extra cheese ×2", not just "extra cheese") — see
/// `ModifierValidator`'s doc comment for how it's validated against a
/// group's min/max.
class OrderLineModifierSelection {
  const OrderLineModifierSelection({
    required this.groupId,
    required this.groupName,
    required this.optionId,
    required this.optionName,
    required this.unitExtraPrice,
    required this.quantity,
  });

  final String groupId;
  final String groupName;
  final String optionId;
  final String optionName;

  /// The extra price for one unit of this option (matches
  /// `ModifierOption.extraPrice`, converted to [Money]).
  final Money unitExtraPrice;

  final int quantity;

  /// `unitExtraPrice * quantity`.
  Money get totalExtraPrice => unitExtraPrice * quantity;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is OrderLineModifierSelection &&
            other.groupId == groupId &&
            other.optionId == optionId &&
            other.unitExtraPrice == unitExtraPrice &&
            other.quantity == quantity);
  }

  @override
  int get hashCode => Object.hash(groupId, optionId, unitExtraPrice, quantity);
}
