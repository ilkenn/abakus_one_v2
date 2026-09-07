/// Which packaging `InventoryItem` (a box, a bag, a cup) a product
/// consumes on acceptance for a given sales channel — AP-5 Sprint 2.
/// Deliberately a **separate** entity from [RecipeIngredientLink]: a
/// product's food recipe and its channel-specific packaging need are
/// independent concerns (dine-in typically needs none at all — reusable
/// plateware isn't consumed stock; takeaway/delivery/marketplace each may
/// need a different box). Packaging is modeled as a normal `InventoryItem`
/// (real, trackable stock), never `PackagingCost` (that stays a pure
/// costing/profitability reference, unrelated to stock consumption).
///
/// [channelCode] is free-text rather than importing `features/orders`'
/// `OrderChannel` enum — mirrors `StockConsumptionChannelPolicy`'s own
/// established reason for the same choice (keeps `features/recipes` from
/// depending on the orders bounded context for reference configuration).
///
/// **Organization-scoped, append-only-by-revision** — same contract as
/// [RecipeIngredientLink].
class ProductPackagingLink {
  const ProductPackagingLink({
    required this.id,
    required this.organizationId,
    required this.productId,
    required this.channelCode,
    required this.packagingInventoryItemId,
    required this.quantity,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String productId;
  final String channelCode;
  final String packagingInventoryItemId;

  /// How many units of the packaging item one unit of [productId] consumes
  /// on this channel (e.g. `1` box, `2` cups).
  final int quantity;

  final DateTime createdAt;
  final int revision;

  ProductPackagingLink copyWith({
    required String packagingInventoryItemId,
    required int quantity,
    required int revision,
  }) {
    return ProductPackagingLink(
      id: id,
      organizationId: organizationId,
      productId: productId,
      channelCode: channelCode,
      packagingInventoryItemId: packagingInventoryItemId,
      quantity: quantity,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
