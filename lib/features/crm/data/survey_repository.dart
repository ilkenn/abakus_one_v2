import '../domain/surveys/survey.dart';

/// Storage for [Survey] — mutable registry entity, mirrors
/// `VisitRewardRuleRepository`.
abstract interface class SurveyRepository {
  Future<void> save(Survey survey);
  Future<Survey?> findById(String surveyId);
  Future<List<Survey>> findAll();
}

class InMemorySurveyRepository implements SurveyRepository {
  final Map<String, Survey> _byId = {};

  @override
  Future<void> save(Survey survey) async => _byId[survey.id] = survey;

  @override
  Future<Survey?> findById(String surveyId) async => _byId[surveyId];

  @override
  Future<List<Survey>> findAll() async => List.unmodifiable(_byId.values);
}
