import '../domain/payment_merchant_method_mapping.dart';

abstract interface class PaymentMerchantMethodMappingRepository {
  Future<void> save(PaymentMerchantMethodMapping mapping);
  Future<List<PaymentMerchantMethodMapping>> findByMerchantAccountId(
      String merchantAccountId);
  Future<PaymentMerchantMethodMapping?> findByMerchantAccountAndMethod(
    String merchantAccountId,
    String paymentMethodId,
  );
}

class InMemoryPaymentMerchantMethodMappingRepository
    implements PaymentMerchantMethodMappingRepository {
  final List<PaymentMerchantMethodMapping> _mappings = [];

  @override
  Future<void> save(PaymentMerchantMethodMapping mapping) async {
    _mappings.removeWhere((m) => m.id == mapping.id);
    _mappings.add(mapping);
  }

  @override
  Future<List<PaymentMerchantMethodMapping>> findByMerchantAccountId(
      String merchantAccountId) async {
    return List.unmodifiable(
      _mappings.where((m) => m.merchantAccountId == merchantAccountId),
    );
  }

  @override
  Future<PaymentMerchantMethodMapping?> findByMerchantAccountAndMethod(
    String merchantAccountId,
    String paymentMethodId,
  ) async {
    for (final mapping in _mappings) {
      if (mapping.merchantAccountId == merchantAccountId &&
          mapping.paymentMethodId == paymentMethodId) {
        return mapping;
      }
    }
    return null;
  }
}
