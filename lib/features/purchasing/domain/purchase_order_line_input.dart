import '../../inventory/domain/quantity.dart';

/// One caller-requested line for `CreatePurchaseOrder` — before a
/// [PurchaseOrderLine] exists, before a price has been snapshotted.
class PurchaseOrderLineInput {
  const PurchaseOrderLineInput({
    required this.supplierProductId,
    required this.orderedQuantity,
  });

  final String supplierProductId;
  final Quantity orderedQuantity;
}
