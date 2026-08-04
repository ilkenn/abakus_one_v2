import '../domain/payment_merchant_account.dart';

abstract interface class PaymentMerchantAccountRepository {
  Future<void> save(PaymentMerchantAccount account);
  Future<PaymentMerchantAccount?> findById(String id);
  Future<List<PaymentMerchantAccount>> findByOrganizationId(
      String organizationId);
}

class InMemoryPaymentMerchantAccountRepository
    implements PaymentMerchantAccountRepository {
  final Map<String, PaymentMerchantAccount> _byId = {};

  @override
  Future<void> save(PaymentMerchantAccount account) async =>
      _byId[account.id] = account;

  @override
  Future<PaymentMerchantAccount?> findById(String id) async => _byId[id];

  @override
  Future<List<PaymentMerchantAccount>> findByOrganizationId(
      String organizationId) async {
    return List.unmodifiable(
      _byId.values.where((a) => a.organizationId == organizationId),
    );
  }
}
