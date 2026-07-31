abstract interface class CustomerFeedbackIdGenerator {
  String nextFeedbackId();
}

class SequentialCustomerFeedbackIdGenerator
    implements CustomerFeedbackIdGenerator {
  SequentialCustomerFeedbackIdGenerator({this.prefix = 'feedback'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextFeedbackId() => '$prefix-${++_sequence}';
}
