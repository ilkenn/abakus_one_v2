import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/stock_consumption_channel_policy_id_generator.dart';
import '../../application/identity/stock_consumption_record_id_generator.dart';
import '../../data/stock_consumption_audit_entry_repository.dart';
import '../../data/stock_consumption_channel_policy_repository.dart';
import '../../data/stock_consumption_record_repository.dart';

/// Central Riverpod wiring for `features/stock_consumption` — Phase 7
/// (`docs/decisions.md` ADR-024). Repository/id-generator providers
/// only, matching the pattern established across every other Phase 7
/// feature — no pre-wired, authorization-policy-baked use-case
/// providers.
final stockConsumptionChannelPolicyRepositoryProvider =
    Provider<StockConsumptionChannelPolicyRepository>((ref) {
  return InMemoryStockConsumptionChannelPolicyRepository();
});

final stockConsumptionChannelPolicyIdGeneratorProvider =
    Provider<StockConsumptionChannelPolicyIdGenerator>((ref) {
  return SequentialStockConsumptionChannelPolicyIdGenerator();
});

final stockConsumptionRecordRepositoryProvider =
    Provider<StockConsumptionRecordRepository>((ref) {
  return InMemoryStockConsumptionRecordRepository();
});

final stockConsumptionRecordIdGeneratorProvider =
    Provider<StockConsumptionRecordIdGenerator>((ref) {
  return SequentialStockConsumptionRecordIdGenerator();
});

final stockConsumptionAuditEntryRepositoryProvider =
    Provider<StockConsumptionAuditEntryRepository>((ref) {
  return InMemoryStockConsumptionAuditEntryRepository();
});
