import '../domain/surveys/survey_response.dart';

/// Append-only storage for [SurveyResponse] — no update or delete method
/// exists at all.
abstract interface class SurveyResponseRepository {
  Future<void> append(SurveyResponse response);
  Future<List<SurveyResponse>> findBySurveyId(String surveyId);
  Future<List<SurveyResponse>> findByCustomerId(String customerId);
}

class InMemorySurveyResponseRepository implements SurveyResponseRepository {
  final List<SurveyResponse> _responses = [];

  @override
  Future<void> append(SurveyResponse response) async {
    _responses.add(response);
  }

  @override
  Future<List<SurveyResponse>> findBySurveyId(String surveyId) async {
    return List.unmodifiable(
      _responses.where((r) => r.surveyId == surveyId),
    );
  }

  @override
  Future<List<SurveyResponse>> findByCustomerId(String customerId) async {
    return List.unmodifiable(
      _responses.where((r) => r.customerId == customerId),
    );
  }
}
