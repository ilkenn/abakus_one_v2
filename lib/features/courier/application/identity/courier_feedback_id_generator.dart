abstract interface class CourierFeedbackIdGenerator {
  String nextFeedbackId();
}

class SequentialCourierFeedbackIdGenerator
    implements CourierFeedbackIdGenerator {
  SequentialCourierFeedbackIdGenerator({this.prefix = 'cfeedback'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextFeedbackId() => '$prefix-${++_sequence}';
}
