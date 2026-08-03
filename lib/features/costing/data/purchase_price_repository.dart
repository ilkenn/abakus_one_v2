import '../domain/purchase_price.dart';

abstract interface class PurchasePriceRepository {
  Future<void> save(PurchasePrice price);
  Future<List<PurchasePrice>> findByIngredientId(String ingredientId);
}

class InMemoryPurchasePriceRepository implements PurchasePriceRepository {
  final List<PurchasePrice> _prices = [];

  @override
  Future<void> save(PurchasePrice price) async {
    _prices.add(price);
  }

  @override
  Future<List<PurchasePrice>> findByIngredientId(String ingredientId) async {
    return List.unmodifiable(
      _prices.where((p) => p.ingredientId == ingredientId),
    );
  }
}
