/// A frozen record of one [ModifierOption] a customer picked from one
/// [ModifierGroup], captured at the moment a product is added to the cart.
///
/// Deliberately flat and self-contained (carries `groupName`/`optionName`
/// as text, not just ids) so cart and order-history UI can display a
/// customization summary without re-resolving the live catalog — the same
/// "snapshot, don't reference" principle `OrderItemSnapshot` already
/// follows for placed orders.
class SelectedModifier {
  final String groupId;
  final String groupName;
  final String optionId;
  final String optionName;
  final double extraPrice;

  const SelectedModifier({
    required this.groupId,
    required this.groupName,
    required this.optionId,
    required this.optionName,
    this.extraPrice = 0.0,
  });
}
