abstract interface class PaymentMerchantMethodMappingIdGenerator {
  String nextPaymentMerchantMethodMappingId();
}

class SequentialPaymentMerchantMethodMappingIdGenerator
    implements PaymentMerchantMethodMappingIdGenerator {
  SequentialPaymentMerchantMethodMappingIdGenerator(
      {this.prefix = 'pay-method-map'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextPaymentMerchantMethodMappingId() => '$prefix-${++_sequence}';
}
