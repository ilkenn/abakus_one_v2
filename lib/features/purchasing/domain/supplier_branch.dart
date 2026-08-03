/// Links a [Supplier] to one branch it actually serves — Phase 7
/// (`docs/decisions.md` ADR-024). A supplier isn't automatically
/// available to every branch in an organization.
class SupplierBranch {
  const SupplierBranch({
    required this.id,
    required this.supplierId,
    required this.branchId,
    required this.createdAt,
  });

  final String id;
  final String supplierId;
  final String branchId;
  final DateTime createdAt;
}
