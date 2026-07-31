abstract interface class SurveyResponseIdGenerator {
  String nextResponseId();
}

class SequentialSurveyResponseIdGenerator implements SurveyResponseIdGenerator {
  SequentialSurveyResponseIdGenerator({this.prefix = 'survey-response'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextResponseId() => '$prefix-${++_sequence}';
}
