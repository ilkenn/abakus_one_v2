abstract interface class SurveyIdGenerator {
  String nextSurveyId();
}

class SequentialSurveyIdGenerator implements SurveyIdGenerator {
  SequentialSurveyIdGenerator({this.prefix = 'survey'});
  final String prefix;
  int _sequence = 0;

  @override
  String nextSurveyId() => '$prefix-${++_sequence}';
}
