abstract interface class PaymentMerchantAccountIdGenerator {
  String nextPaymentMerchantAccountId();
}

class SequentialPaymentMerchantAccountIdGenerator
    implements PaymentMerchantAccountIdGenerator {
  SequentialPaymentMerchantAccountIdGenerator({this.prefix = 'pay-merchant'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextPaymentMerchantAccountId() => '$prefix-${++_sequence}';
}
