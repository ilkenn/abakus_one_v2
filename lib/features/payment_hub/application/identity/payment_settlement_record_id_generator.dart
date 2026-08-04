abstract interface class PaymentSettlementRecordIdGenerator {
  String nextPaymentSettlementRecordId();
}

class SequentialPaymentSettlementRecordIdGenerator
    implements PaymentSettlementRecordIdGenerator {
  SequentialPaymentSettlementRecordIdGenerator(
      {this.prefix = 'pay-settlement'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextPaymentSettlementRecordId() => '$prefix-${++_sequence}';
}
