import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/survey_repository.dart';
import '../../data/survey_response_repository.dart';
import '../../domain/surveys/survey_question_type.dart';
import '../../domain/surveys/survey_statistics.dart';

/// Assembles one survey's [SurveyStatistics] — Sprint 5D. A pure
/// per-question response-distribution aggregator (mirrors
/// `BuildCourierDailyOperationsReport`'s aggregation-only discipline: no
/// new detection logic, just counting/averaging already-recorded
/// answers).
class BuildSurveyStatistics {
  const BuildSurveyStatistics({
    required Clock clock,
    required SurveyRepository surveyRepository,
    required SurveyResponseRepository responseRepository,
  })  : _clock = clock,
        _surveyRepository = surveyRepository,
        _responseRepository = responseRepository;

  final Clock _clock;
  final SurveyRepository _surveyRepository;
  final SurveyResponseRepository _responseRepository;

  Future<SurveyStatistics> call({required String surveyId}) async {
    final survey = await _surveyRepository.findById(surveyId);
    if (survey == null) {
      throw UnknownCrmEntityViolation(entityName: 'Survey', id: surveyId);
    }

    final responses = await _responseRepository.findBySurveyId(surveyId);

    final questionStatistics = <SurveyQuestionStatistics>[];
    for (final question in survey.questions) {
      final answersForQuestion = [
        for (final response in responses)
          for (final answer in response.answers)
            if (answer.questionId == question.id) answer,
      ];

      double? averageNumericValue;
      final optionCounts = <String, int>{};
      int? booleanTrueCount;
      int? booleanFalseCount;

      switch (question.type) {
        case SurveyQuestionType.rating:
        case SurveyQuestionType.stars:
        case SurveyQuestionType.emoji:
          final values = answersForQuestion
              .map((a) => a.numericValue)
              .whereType<int>()
              .toList();
          if (values.isNotEmpty) {
            averageNumericValue =
                values.reduce((a, b) => a + b) / values.length;
          }
        case SurveyQuestionType.multipleChoice:
          for (final option in question.options) {
            optionCounts[option.id] = 0;
          }
          for (final answer in answersForQuestion) {
            for (final optionId in answer.selectedOptionIds) {
              optionCounts[optionId] = (optionCounts[optionId] ?? 0) + 1;
            }
          }
        case SurveyQuestionType.boolean:
          booleanTrueCount =
              answersForQuestion.where((a) => a.booleanValue == true).length;
          booleanFalseCount =
              answersForQuestion.where((a) => a.booleanValue == false).length;
        case SurveyQuestionType.text:
          break;
      }

      questionStatistics.add(SurveyQuestionStatistics(
        questionId: question.id,
        responseCount: answersForQuestion.length,
        averageNumericValue: averageNumericValue,
        optionCounts: optionCounts,
        booleanTrueCount: booleanTrueCount,
        booleanFalseCount: booleanFalseCount,
      ));
    }

    return SurveyStatistics(
      surveyId: surveyId,
      totalResponses: responses.length,
      questionStatistics: questionStatistics,
      generatedAt: _clock.now(),
    );
  }
}
