import '../domain/supplier_branch.dart';

abstract interface class SupplierBranchRepository {
  Future<void> save(SupplierBranch supplierBranch);
  Future<List<SupplierBranch>> findByBranchId(String branchId);
}

class InMemorySupplierBranchRepository implements SupplierBranchRepository {
  final List<SupplierBranch> _links = [];

  @override
  Future<void> save(SupplierBranch supplierBranch) async {
    _links.add(supplierBranch);
  }

  @override
  Future<List<SupplierBranch>> findByBranchId(String branchId) async {
    return List.unmodifiable(_links.where((l) => l.branchId == branchId));
  }
}
