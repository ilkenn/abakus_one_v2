import '../../../shared/models/money.dart';
import '../../inventory/domain/quantity.dart';

/// One line of a [PurchaseOrder] — Phase 7 (`docs/decisions.md`
/// ADR-024). [unitPriceAtOrder] is a frozen snapshot of the
/// [SupplierProduct]'s price at the moment the order was created —
/// never a live reference to [SupplierPrice].
class PurchaseOrderLine {
  const PurchaseOrderLine({
    required this.id,
    required this.purchaseOrderId,
    required this.supplierProductId,
    required this.orderedQuantity,
    required this.unitPriceAtOrder,
  });

  final String id;
  final String purchaseOrderId;
  final String supplierProductId;
  final Quantity orderedQuantity;
  final Money unitPriceAtOrder;
}
