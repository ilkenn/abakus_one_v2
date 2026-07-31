abstract interface class CustomerFeedbackStatusEventIdGenerator {
  String nextEventId();
}

class SequentialCustomerFeedbackStatusEventIdGenerator
    implements CustomerFeedbackStatusEventIdGenerator {
  SequentialCustomerFeedbackStatusEventIdGenerator({
    this.prefix = 'feedback-status',
  });
  final String prefix;
  int _sequence = 0;

  @override
  String nextEventId() => '$prefix-${++_sequence}';
}
