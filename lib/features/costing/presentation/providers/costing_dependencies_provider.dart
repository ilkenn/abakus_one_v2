import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/cost_calculation_result_id_generator.dart';
import '../../application/identity/purchase_price_id_generator.dart';
import '../../application/identity/standard_ingredient_cost_id_generator.dart';
import '../../data/cost_calculation_result_repository.dart';
import '../../data/costing_audit_entry_repository.dart';
import '../../data/delivery_channel_cost_repository.dart';
import '../../data/labor_cost_allocation_config_repository.dart';
import '../../data/overhead_allocation_config_repository.dart';
import '../../data/packaging_cost_repository.dart';
import '../../data/purchase_price_repository.dart';
import '../../data/standard_ingredient_cost_repository.dart';

/// Central Riverpod wiring for `features/costing` — Phase 7
/// (`docs/decisions.md` ADR-024). Repository/id-generator providers
/// only, matching the pattern established across every other Phase 7
/// feature — no pre-wired, authorization-policy-baked use-case
/// providers.
final purchasePriceRepositoryProvider =
    Provider<PurchasePriceRepository>((ref) {
  return InMemoryPurchasePriceRepository();
});

final purchasePriceIdGeneratorProvider =
    Provider<PurchasePriceIdGenerator>((ref) {
  return SequentialPurchasePriceIdGenerator();
});

final standardIngredientCostRepositoryProvider =
    Provider<StandardIngredientCostRepository>((ref) {
  return InMemoryStandardIngredientCostRepository();
});

final standardIngredientCostIdGeneratorProvider =
    Provider<StandardIngredientCostIdGenerator>((ref) {
  return SequentialStandardIngredientCostIdGenerator();
});

final costCalculationResultRepositoryProvider =
    Provider<CostCalculationResultRepository>((ref) {
  return InMemoryCostCalculationResultRepository();
});

final costCalculationResultIdGeneratorProvider =
    Provider<CostCalculationResultIdGenerator>((ref) {
  return SequentialCostCalculationResultIdGenerator();
});

final costingAuditEntryRepositoryProvider =
    Provider<CostingAuditEntryRepository>((ref) {
  return InMemoryCostingAuditEntryRepository();
});

final packagingCostRepositoryProvider =
    Provider<PackagingCostRepository>((ref) {
  return InMemoryPackagingCostRepository();
});

final deliveryChannelCostRepositoryProvider =
    Provider<DeliveryChannelCostRepository>((ref) {
  return InMemoryDeliveryChannelCostRepository();
});

final laborCostAllocationConfigRepositoryProvider =
    Provider<LaborCostAllocationConfigRepository>((ref) {
  return InMemoryLaborCostAllocationConfigRepository();
});

final overheadAllocationConfigRepositoryProvider =
    Provider<OverheadAllocationConfigRepository>((ref) {
  return InMemoryOverheadAllocationConfigRepository();
});
