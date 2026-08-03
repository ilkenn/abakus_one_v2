import 'purchase_order_status.dart';

/// A restaurant's order to a [Supplier] — Phase 7
/// (`docs/decisions.md` ADR-024). No accounting/e-invoice integration
/// — purely an operational purchasing record (explicit out-of-scope
/// per the Phase 7 kickoff).
class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.organizationId,
    required this.branchId,
    required this.supplierId,
    required this.status,
    required this.createdByStaffId,
    required this.createdAt,
    this.submittedAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String branchId;
  final String supplierId;
  final PurchaseOrderStatus status;
  final String createdByStaffId;
  final DateTime createdAt;
  final DateTime? submittedAt;
  final int revision;

  PurchaseOrder copyWith({
    required PurchaseOrderStatus status,
    DateTime? submittedAt,
    required int revision,
  }) {
    return PurchaseOrder(
      id: id,
      organizationId: organizationId,
      branchId: branchId,
      supplierId: supplierId,
      status: status,
      createdByStaffId: createdByStaffId,
      createdAt: createdAt,
      submittedAt: submittedAt ?? this.submittedAt,
      revision: revision,
    );
  }
}
