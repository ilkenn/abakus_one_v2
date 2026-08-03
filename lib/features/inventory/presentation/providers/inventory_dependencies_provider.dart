import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/ingredient_id_generator.dart';
import '../../application/identity/inventory_item_id_generator.dart';
import '../../application/identity/stock_adjustment_id_generator.dart';
import '../../application/identity/stock_location_id_generator.dart';
import '../../application/identity/stock_lot_id_generator.dart';
import '../../application/identity/stock_movement_id_generator.dart';
import '../../application/identity/warehouse_id_generator.dart';
import '../../data/branch_stock_repository.dart';
import '../../data/expiry_record_repository.dart';
import '../../data/ingredient_repository.dart';
import '../../data/inventory_audit_entry_repository.dart';
import '../../data/inventory_item_repository.dart';
import '../../data/stock_adjustment_repository.dart';
import '../../data/stock_count_line_repository.dart';
import '../../data/stock_count_repository.dart';
import '../../data/stock_location_repository.dart';
import '../../data/stock_lot_repository.dart';
import '../../data/stock_movement_repository.dart';
import '../../data/stock_reservation_repository.dart';
import '../../data/unit_conversion_repository.dart';
import '../../data/warehouse_repository.dart';
import '../../data/waste_record_repository.dart';

/// Central Riverpod wiring for `features/inventory` — Phase 7
/// (`docs/decisions.md` ADR-024). Repository/id-generator providers
/// only — no pre-wired, authorization-policy-baked use-case providers.
/// Every screen constructs its use cases inline with its own injected
/// `authorizationPolicy`, matching the pattern corrected in 7E's
/// `SetupTemplatesScreen` (a pre-wired use-case provider silently bakes
/// in the real production policy, defeating test injection).
final ingredientRepositoryProvider = Provider<IngredientRepository>((ref) {
  return InMemoryIngredientRepository();
});

final ingredientIdGeneratorProvider = Provider<IngredientIdGenerator>((ref) {
  return SequentialIngredientIdGenerator();
});

final inventoryItemRepositoryProvider =
    Provider<InventoryItemRepository>((ref) {
  return InMemoryInventoryItemRepository();
});

final inventoryItemIdGeneratorProvider =
    Provider<InventoryItemIdGenerator>((ref) {
  return SequentialInventoryItemIdGenerator();
});

final stockLocationRepositoryProvider =
    Provider<StockLocationRepository>((ref) {
  return InMemoryStockLocationRepository();
});

final stockLocationIdGeneratorProvider =
    Provider<StockLocationIdGenerator>((ref) {
  return SequentialStockLocationIdGenerator();
});

final warehouseRepositoryProvider = Provider<WarehouseRepository>((ref) {
  return InMemoryWarehouseRepository();
});

final warehouseIdGeneratorProvider = Provider<WarehouseIdGenerator>((ref) {
  return SequentialWarehouseIdGenerator();
});

final branchStockRepositoryProvider = Provider<BranchStockRepository>((ref) {
  return InMemoryBranchStockRepository();
});

final stockLotRepositoryProvider = Provider<StockLotRepository>((ref) {
  return InMemoryStockLotRepository();
});

final stockLotIdGeneratorProvider = Provider<StockLotIdGenerator>((ref) {
  return SequentialStockLotIdGenerator();
});

final stockMovementRepositoryProvider =
    Provider<StockMovementRepository>((ref) {
  return InMemoryStockMovementRepository();
});

final stockMovementIdGeneratorProvider =
    Provider<StockMovementIdGenerator>((ref) {
  return SequentialStockMovementIdGenerator();
});

final stockAdjustmentRepositoryProvider =
    Provider<StockAdjustmentRepository>((ref) {
  return InMemoryStockAdjustmentRepository();
});

final stockAdjustmentIdGeneratorProvider =
    Provider<StockAdjustmentIdGenerator>((ref) {
  return SequentialStockAdjustmentIdGenerator();
});

final stockCountRepositoryProvider = Provider<StockCountRepository>((ref) {
  return InMemoryStockCountRepository();
});

final stockCountLineRepositoryProvider =
    Provider<StockCountLineRepository>((ref) {
  return InMemoryStockCountLineRepository();
});

final wasteRecordRepositoryProvider = Provider<WasteRecordRepository>((ref) {
  return InMemoryWasteRecordRepository();
});

final expiryRecordRepositoryProvider = Provider<ExpiryRecordRepository>((ref) {
  return InMemoryExpiryRecordRepository();
});

final unitConversionRepositoryProvider =
    Provider<UnitConversionRepository>((ref) {
  return InMemoryUnitConversionRepository();
});

final stockReservationRepositoryProvider =
    Provider<StockReservationRepository>((ref) {
  return InMemoryStockReservationRepository();
});

final inventoryAuditEntryRepositoryProvider =
    Provider<InventoryAuditEntryRepository>((ref) {
  return InMemoryInventoryAuditEntryRepository();
});
