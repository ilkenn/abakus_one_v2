import '../domain/supplier_price.dart';

abstract interface class SupplierPriceRepository {
  Future<void> save(SupplierPrice price);
  Future<List<SupplierPrice>> findBySupplierProductId(String supplierProductId);
}

class InMemorySupplierPriceRepository implements SupplierPriceRepository {
  final List<SupplierPrice> _prices = [];

  @override
  Future<void> save(SupplierPrice price) async {
    _prices.add(price);
  }

  @override
  Future<List<SupplierPrice>> findBySupplierProductId(
      String supplierProductId) async {
    return List.unmodifiable(
      _prices.where((p) => p.supplierProductId == supplierProductId),
    );
  }
}
