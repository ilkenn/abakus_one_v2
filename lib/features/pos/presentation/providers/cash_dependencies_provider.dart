import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/cash_adjustment_id_generator.dart';
import '../../application/identity/cash_count_id_generator.dart';
import '../../application/identity/cash_drawer_id_generator.dart';
import '../../application/identity/cash_movement_id_generator.dart';
import '../../application/identity/cash_reconciliation_id_generator.dart';
import '../../application/identity/cash_session_id_generator.dart';
import '../../data/cash_adjustment_repository.dart';
import '../../data/cash_audit_entry_repository.dart';
import '../../data/cash_count_repository.dart';
import '../../data/cash_drawer_repository.dart';
import '../../data/cash_movement_repository.dart';
import '../../data/cash_reconciliation_repository.dart';
import '../../data/cash_session_repository.dart';

/// Every cash-management repository/id-generator currently in use — all
/// in-memory today, no backend persistence exists yet. Bundled in one
/// file (unlike most single-concern provider files elsewhere in this
/// codebase) since Phase 3 Sprint 3E's screens each depend on several of
/// these at once, and none has independent lifecycle/testing needs
/// beyond what the others already establish.
final cashDrawerRepositoryProvider = Provider<CashDrawerRepository>((ref) {
  return InMemoryCashDrawerRepository();
});

final cashSessionRepositoryProvider = Provider<CashSessionRepository>((ref) {
  return InMemoryCashSessionRepository();
});

final cashMovementRepositoryProvider = Provider<CashMovementRepository>((ref) {
  return InMemoryCashMovementRepository();
});

final cashCountRepositoryProvider = Provider<CashCountRepository>((ref) {
  return InMemoryCashCountRepository();
});

final cashReconciliationRepositoryProvider =
    Provider<CashReconciliationRepository>((ref) {
  return InMemoryCashReconciliationRepository();
});

final cashAdjustmentRepositoryProvider =
    Provider<CashAdjustmentRepository>((ref) {
  return InMemoryCashAdjustmentRepository();
});

final cashAuditEntryRepositoryProvider =
    Provider<CashAuditEntryRepository>((ref) {
  return InMemoryCashAuditEntryRepository();
});

final cashDrawerIdGeneratorProvider = Provider<CashDrawerIdGenerator>((ref) {
  return SequentialCashDrawerIdGenerator();
});

final cashSessionIdGeneratorProvider = Provider<CashSessionIdGenerator>((ref) {
  return SequentialCashSessionIdGenerator();
});

final cashMovementIdGeneratorProvider =
    Provider<CashMovementIdGenerator>((ref) {
  return SequentialCashMovementIdGenerator();
});

final cashCountIdGeneratorProvider = Provider<CashCountIdGenerator>((ref) {
  return SequentialCashCountIdGenerator();
});

final cashReconciliationIdGeneratorProvider =
    Provider<CashReconciliationIdGenerator>((ref) {
  return SequentialCashReconciliationIdGenerator();
});

final cashAdjustmentIdGeneratorProvider =
    Provider<CashAdjustmentIdGenerator>((ref) {
  return SequentialCashAdjustmentIdGenerator();
});
