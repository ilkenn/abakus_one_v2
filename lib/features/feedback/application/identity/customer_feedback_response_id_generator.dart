abstract interface class CustomerFeedbackResponseIdGenerator {
  String nextResponseId();
}

class SequentialCustomerFeedbackResponseIdGenerator
    implements CustomerFeedbackResponseIdGenerator {
  SequentialCustomerFeedbackResponseIdGenerator({
    this.prefix = 'feedback-response',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextResponseId() => '$prefix-${++_sequence}';
}
