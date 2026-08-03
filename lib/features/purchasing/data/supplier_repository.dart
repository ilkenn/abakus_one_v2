import '../domain/supplier.dart';

abstract interface class SupplierRepository {
  Future<void> save(Supplier supplier);
  Future<Supplier?> findById(String id);
  Future<List<Supplier>> findByOrganizationId(String organizationId);
}

class InMemorySupplierRepository implements SupplierRepository {
  final Map<String, Supplier> _byId = {};

  @override
  Future<void> save(Supplier supplier) async => _byId[supplier.id] = supplier;

  @override
  Future<Supplier?> findById(String id) async => _byId[id];

  @override
  Future<List<Supplier>> findByOrganizationId(String organizationId) async {
    return List.unmodifiable(
      _byId.values.where((s) => s.organizationId == organizationId),
    );
  }
}
