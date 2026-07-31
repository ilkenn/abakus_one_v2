import 'survey_answer.dart';

/// One immutable, append-only survey submission — Sprint 5D's Survey
/// Engine.
class SurveyResponse {
  const SurveyResponse({
    required this.id,
    required this.surveyId,
    required this.customerId,
    required this.answers,
    required this.submittedAt,
  });

  final String id;
  final String surveyId;
  final String customerId;
  final List<SurveyAnswer> answers;
  final DateTime submittedAt;
}
