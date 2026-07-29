import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/courier_cash_collection_id_generator.dart';
import '../../application/identity/courier_cash_declaration_id_generator.dart';
import '../../application/identity/courier_settlement_adjustment_id_generator.dart';
import '../../application/identity/courier_settlement_id_generator.dart';
import '../../application/identity/courier_settlement_session_id_generator.dart';
import '../../data/courier_cash_collection_repository.dart';
import '../../data/courier_cash_declaration_repository.dart';
import '../../data/courier_settlement_adjustment_repository.dart';
import '../../data/courier_settlement_audit_entry_repository.dart';
import '../../data/courier_settlement_repository.dart';
import '../../data/courier_settlement_session_repository.dart';

/// Every courier-settlement repository/id-generator currently in use —
/// all in-memory today, no backend persistence exists yet. Bundled in one
/// file, mirroring `cash_dependencies_provider.dart`'s own precedent
/// (Sprint 3E) for the same reason: this sprint's screens each depend on
/// several of these at once, and none has independent lifecycle/testing
/// needs beyond what the others already establish.
final courierSettlementSessionRepositoryProvider =
    Provider<CourierSettlementSessionRepository>((ref) {
  return InMemoryCourierSettlementSessionRepository();
});

final courierCashCollectionRepositoryProvider =
    Provider<CourierCashCollectionRepository>((ref) {
  return InMemoryCourierCashCollectionRepository();
});

final courierCashDeclarationRepositoryProvider =
    Provider<CourierCashDeclarationRepository>((ref) {
  return InMemoryCourierCashDeclarationRepository();
});

final courierSettlementRepositoryProvider =
    Provider<CourierSettlementRepository>((ref) {
  return InMemoryCourierSettlementRepository();
});

final courierSettlementAdjustmentRepositoryProvider =
    Provider<CourierSettlementAdjustmentRepository>((ref) {
  return InMemoryCourierSettlementAdjustmentRepository();
});

final courierSettlementAuditEntryRepositoryProvider =
    Provider<CourierSettlementAuditEntryRepository>((ref) {
  return InMemoryCourierSettlementAuditEntryRepository();
});

final courierSettlementSessionIdGeneratorProvider =
    Provider<CourierSettlementSessionIdGenerator>((ref) {
  return SequentialCourierSettlementSessionIdGenerator();
});

final courierCashCollectionIdGeneratorProvider =
    Provider<CourierCashCollectionIdGenerator>((ref) {
  return SequentialCourierCashCollectionIdGenerator();
});

final courierCashDeclarationIdGeneratorProvider =
    Provider<CourierCashDeclarationIdGenerator>((ref) {
  return SequentialCourierCashDeclarationIdGenerator();
});

final courierSettlementIdGeneratorProvider =
    Provider<CourierSettlementIdGenerator>((ref) {
  return SequentialCourierSettlementIdGenerator();
});

final courierSettlementAdjustmentIdGeneratorProvider =
    Provider<CourierSettlementAdjustmentIdGenerator>((ref) {
  return SequentialCourierSettlementAdjustmentIdGenerator();
});
