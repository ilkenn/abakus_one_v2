import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/profitability_calculation_result_id_generator.dart';
import '../../application/identity/profitability_threshold_config_id_generator.dart';
import '../../data/profitability_audit_entry_repository.dart';
import '../../data/profitability_calculation_result_repository.dart';
import '../../data/profitability_threshold_config_repository.dart';

/// Central Riverpod wiring for `features/profitability` — Phase 7
/// (`docs/decisions.md` ADR-024). Repository/id-generator providers
/// only, matching the pattern established across every other Phase 7
/// feature — no pre-wired, authorization-policy-baked use-case
/// providers.
final profitabilityThresholdConfigRepositoryProvider =
    Provider<ProfitabilityThresholdConfigRepository>((ref) {
  return InMemoryProfitabilityThresholdConfigRepository();
});

final profitabilityThresholdConfigIdGeneratorProvider =
    Provider<ProfitabilityThresholdConfigIdGenerator>((ref) {
  return SequentialProfitabilityThresholdConfigIdGenerator();
});

final profitabilityCalculationResultRepositoryProvider =
    Provider<ProfitabilityCalculationResultRepository>((ref) {
  return InMemoryProfitabilityCalculationResultRepository();
});

final profitabilityCalculationResultIdGeneratorProvider =
    Provider<ProfitabilityCalculationResultIdGenerator>((ref) {
  return SequentialProfitabilityCalculationResultIdGenerator();
});

final profitabilityAuditEntryRepositoryProvider =
    Provider<ProfitabilityAuditEntryRepository>((ref) {
  return InMemoryProfitabilityAuditEntryRepository();
});
