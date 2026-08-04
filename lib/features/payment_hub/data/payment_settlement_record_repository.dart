import '../domain/payment_settlement_record.dart';

abstract interface class PaymentSettlementRecordRepository {
  Future<void> save(PaymentSettlementRecord record);
  Future<PaymentSettlementRecord?> findByExternalSettlementId(
      String externalSettlementId);
  Future<List<PaymentSettlementRecord>> findByMerchantAccountId(
      String merchantAccountId);
}

class InMemoryPaymentSettlementRecordRepository
    implements PaymentSettlementRecordRepository {
  final Map<String, PaymentSettlementRecord> _byExternalSettlementId = {};

  @override
  Future<void> save(PaymentSettlementRecord record) async =>
      _byExternalSettlementId[record.externalSettlementId] = record;

  @override
  Future<PaymentSettlementRecord?> findByExternalSettlementId(
      String externalSettlementId) async {
    return _byExternalSettlementId[externalSettlementId];
  }

  @override
  Future<List<PaymentSettlementRecord>> findByMerchantAccountId(
      String merchantAccountId) async {
    return List.unmodifiable(
      _byExternalSettlementId.values
          .where((r) => r.merchantAccountId == merchantAccountId),
    );
  }
}
