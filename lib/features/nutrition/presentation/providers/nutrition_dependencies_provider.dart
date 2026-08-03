import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/nutrition_calculation_result_id_generator.dart';
import '../../application/identity/nutrition_reference_entry_id_generator.dart';
import '../../data/nutrition_audit_entry_repository.dart';
import '../../data/nutrition_calculation_result_repository.dart';
import '../../data/nutrition_reference_entry_repository.dart';

/// Central Riverpod wiring for `features/nutrition` — Phase 7
/// (`docs/decisions.md` ADR-024). Repository/id-generator providers
/// only, matching the pattern established in `features/inventory`/
/// `features/recipes` — no pre-wired, authorization-policy-baked
/// use-case providers.
final nutritionReferenceEntryRepositoryProvider =
    Provider<NutritionReferenceEntryRepository>((ref) {
  return InMemoryNutritionReferenceEntryRepository();
});

final nutritionReferenceEntryIdGeneratorProvider =
    Provider<NutritionReferenceEntryIdGenerator>((ref) {
  return SequentialNutritionReferenceEntryIdGenerator();
});

final nutritionAuditEntryRepositoryProvider =
    Provider<NutritionAuditEntryRepository>((ref) {
  return InMemoryNutritionAuditEntryRepository();
});

final nutritionCalculationResultRepositoryProvider =
    Provider<NutritionCalculationResultRepository>((ref) {
  return InMemoryNutritionCalculationResultRepository();
});

final nutritionCalculationResultIdGeneratorProvider =
    Provider<NutritionCalculationResultIdGenerator>((ref) {
  return SequentialNutritionCalculationResultIdGenerator();
});
