import '../domain/supplier_product.dart';

abstract interface class SupplierProductRepository {
  Future<void> save(SupplierProduct product);
  Future<SupplierProduct?> findById(String id);
  Future<List<SupplierProduct>> findBySupplierId(String supplierId);
}

class InMemorySupplierProductRepository implements SupplierProductRepository {
  final Map<String, SupplierProduct> _byId = {};

  @override
  Future<void> save(SupplierProduct product) async =>
      _byId[product.id] = product;

  @override
  Future<SupplierProduct?> findById(String id) async => _byId[id];

  @override
  Future<List<SupplierProduct>> findBySupplierId(String supplierId) async {
    return List.unmodifiable(
      _byId.values.where((p) => p.supplierId == supplierId),
    );
  }
}
