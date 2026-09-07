import 'branch_stock.dart';
import 'inventory_item.dart';

/// AP-5 Sprint 5 — a manager-facing summary of one [InventoryItem]'s
/// on-hand health at a branch, derived purely from [BranchStock] and the
/// item's own [InventoryItem.reorderThreshold]/[InventoryItem
/// .negativeStockPolicy]. Never stored — always recomputed, mirroring
/// `KitchenDelayState`'s own "pure computed value object" precedent
/// (`lib/features/pos/domain/kds/kitchen_delay_state.dart`).
enum StockHealthStatus { healthy, lowStock, outOfStock }

extension StockHealthStatusResolver on StockHealthStatus {
  /// `branchStock == null` (nothing tracked yet at this branch) is
  /// treated as [StockHealthStatus.healthy] — mirrors
  /// `InventoryScreen`'s own existing "Bu şubede stok kaydı yok" neutral
  /// treatment, never a fabricated warning for data that doesn't exist.
  ///
  /// On-hand at or below zero is always [StockHealthStatus.outOfStock] —
  /// this covers both an exact-zero balance and, when
  /// [NegativeStockPolicy.warn]/`.allow` let a movement push it negative,
  /// a genuinely negative balance too. This is the same `<= 0` rule
  /// `acceptOrderLine.ts`'s server-side out-of-stock guard uses (AP-5
  /// Sprint 5) — kept deliberately identical in meaning across languages,
  /// the same status-shape-parity precedent `KitchenLineStatus` already
  /// established, not literal code sharing.
  ///
  /// Otherwise, [StockHealthStatus.lowStock] once on-hand is at or below
  /// [InventoryItem.reorderThreshold] — `null` (no threshold configured)
  /// means low-stock can never be computed for that item, never a
  /// fabricated default threshold.
  static StockHealthStatus compute({
    required InventoryItem item,
    required BranchStock? branchStock,
  }) {
    if (branchStock == null) return StockHealthStatus.healthy;
    if (branchStock.quantityOnHand.smallestUnits <= 0) {
      return StockHealthStatus.outOfStock;
    }
    final threshold = item.reorderThreshold;
    if (threshold != null && branchStock.quantityOnHand <= threshold) {
      return StockHealthStatus.lowStock;
    }
    return StockHealthStatus.healthy;
  }
}
