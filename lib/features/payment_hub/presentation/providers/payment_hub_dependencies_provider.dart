import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/payment_merchant_account_id_generator.dart';
import '../../application/identity/payment_merchant_method_mapping_id_generator.dart';
import '../../application/identity/payment_settlement_record_id_generator.dart';
import '../../data/payment_hub_audit_entry_repository.dart';
import '../../data/payment_merchant_account_repository.dart';
import '../../data/payment_merchant_method_mapping_repository.dart';
import '../../data/payment_settlement_record_repository.dart';

/// Central Riverpod wiring for `features/payment_hub` — Phase 8
/// (`docs/decisions.md` ADR-025). Repository/id-generator providers
/// only, matching every other Phase 7/8 dependencies-provider file's
/// convention.
final paymentMerchantAccountRepositoryProvider =
    Provider<PaymentMerchantAccountRepository>((ref) {
  return InMemoryPaymentMerchantAccountRepository();
});

final paymentMerchantAccountIdGeneratorProvider =
    Provider<PaymentMerchantAccountIdGenerator>((ref) {
  return SequentialPaymentMerchantAccountIdGenerator();
});

final paymentMerchantMethodMappingRepositoryProvider =
    Provider<PaymentMerchantMethodMappingRepository>((ref) {
  return InMemoryPaymentMerchantMethodMappingRepository();
});

final paymentMerchantMethodMappingIdGeneratorProvider =
    Provider<PaymentMerchantMethodMappingIdGenerator>((ref) {
  return SequentialPaymentMerchantMethodMappingIdGenerator();
});

final paymentSettlementRecordRepositoryProvider =
    Provider<PaymentSettlementRecordRepository>((ref) {
  return InMemoryPaymentSettlementRecordRepository();
});

final paymentSettlementRecordIdGeneratorProvider =
    Provider<PaymentSettlementRecordIdGenerator>((ref) {
  return SequentialPaymentSettlementRecordIdGenerator();
});

final paymentHubAuditEntryRepositoryProvider =
    Provider<PaymentHubAuditEntryRepository>((ref) {
  return InMemoryPaymentHubAuditEntryRepository();
});
