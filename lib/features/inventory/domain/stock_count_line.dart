import 'quantity.dart';

/// One counted [InventoryItem] within a [StockCount] — Phase 7
/// (`docs/decisions.md` ADR-024). [varianceQuantity] is always
/// `countedQuantity - expectedQuantity`, computed once at construction
/// — never independently supplied, so a line can't be internally
/// inconsistent (mirrors `OrderLine`'s own "computed once, at
/// construction" discipline).
class StockCountLine {
  StockCountLine({
    required this.id,
    required this.countId,
    required this.inventoryItemId,
    required this.expectedQuantity,
    required this.countedQuantity,
  }) : varianceQuantity = countedQuantity - expectedQuantity;

  final String id;
  final String countId;
  final String inventoryItemId;
  final Quantity expectedQuantity;
  final Quantity countedQuantity;
  final Quantity varianceQuantity;
}
