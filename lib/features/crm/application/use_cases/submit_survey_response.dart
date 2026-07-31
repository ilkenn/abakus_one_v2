import '../../../../core/errors/business_rule_violation.dart';
import '../../../../core/utils/clock.dart';
import '../../data/survey_repository.dart';
import '../../data/survey_response_repository.dart';
import '../../domain/surveys/survey.dart';
import '../../domain/surveys/survey_answer.dart';
import '../../domain/surveys/survey_question.dart';
import '../../domain/surveys/survey_question_type.dart';
import '../../domain/surveys/survey_response.dart';
import '../identity/survey_response_id_generator.dart';

/// A customer submits a [SurveyResponse] — no authorization gate (a
/// customer's own submission, mirrors `SetCustomerCategory`'s
/// self-service shape). Validates the answer set exactly covers the
/// survey's questions and that each answer's shape matches its
/// question's [SurveyQuestionType] before anything is persisted.
class SubmitSurveyResponse {
  const SubmitSurveyResponse({
    required Clock clock,
    required SurveyResponseIdGenerator idGenerator,
    required SurveyRepository surveyRepository,
    required SurveyResponseRepository responseRepository,
    this.numericScaleMin = 1,
    this.numericScaleMax = 5,
  })  : _clock = clock,
        _idGenerator = idGenerator,
        _surveyRepository = surveyRepository,
        _responseRepository = responseRepository;

  final Clock _clock;
  final SurveyResponseIdGenerator _idGenerator;
  final SurveyRepository _surveyRepository;
  final SurveyResponseRepository _responseRepository;

  /// The valid inclusive range for a [SurveyQuestionType.rating]/`.stars`/
  /// `.emoji` answer's `numericValue` — adjustable, never hardcoded
  /// inline in [call].
  final int numericScaleMin;
  final int numericScaleMax;

  Future<SurveyResponse> call({
    required String surveyId,
    required String customerId,
    required List<SurveyAnswer> answers,
  }) async {
    final survey = await _surveyRepository.findById(surveyId);
    if (survey == null) {
      throw UnknownCrmEntityViolation(entityName: 'Survey', id: surveyId);
    }

    final now = _clock.now();
    if (!survey.isCurrentlyActive(now)) {
      throw InvalidSurveyResponseViolation(
        reason: 'Survey "$surveyId" is not currently active',
      );
    }

    _validateAnswers(survey: survey, answers: answers);

    final response = SurveyResponse(
      id: _idGenerator.nextResponseId(),
      surveyId: surveyId,
      customerId: customerId,
      answers: answers,
      submittedAt: now,
    );
    await _responseRepository.append(response);
    return response;
  }

  void _validateAnswers({
    required Survey survey,
    required List<SurveyAnswer> answers,
  }) {
    final questionIds = survey.questions.map((q) => q.id).toSet();
    final answeredIds = answers.map((a) => a.questionId).toSet();
    if (answeredIds.length != answers.length ||
        answeredIds.length != questionIds.length ||
        !answeredIds.containsAll(questionIds)) {
      throw const InvalidSurveyResponseViolation(
        reason: 'answers must cover exactly the survey\'s questions',
      );
    }

    final questionsById = {for (final q in survey.questions) q.id: q};
    for (final answer in answers) {
      final question = questionsById[answer.questionId]!;
      _validateAnswerShape(question, answer);
    }
  }

  void _validateAnswerShape(SurveyQuestion question, SurveyAnswer answer) {
    switch (question.type) {
      case SurveyQuestionType.rating:
      case SurveyQuestionType.stars:
      case SurveyQuestionType.emoji:
        final value = answer.numericValue;
        if (value == null ||
            value < numericScaleMin ||
            value > numericScaleMax) {
          throw InvalidSurveyResponseViolation(
            reason: 'question "${question.id}" requires a numericValue '
                'between $numericScaleMin and $numericScaleMax',
          );
        }
      case SurveyQuestionType.multipleChoice:
        final validOptionIds = question.options.map((o) => o.id).toSet();
        if (answer.selectedOptionIds.isEmpty ||
            !validOptionIds.containsAll(answer.selectedOptionIds)) {
          throw InvalidSurveyResponseViolation(
            reason: 'question "${question.id}" requires at least one '
                'valid selected option',
          );
        }
      case SurveyQuestionType.text:
        if (answer.textValue == null || answer.textValue!.trim().isEmpty) {
          throw InvalidSurveyResponseViolation(
            reason: 'question "${question.id}" requires a non-empty '
                'textValue',
          );
        }
      case SurveyQuestionType.boolean:
        if (answer.booleanValue == null) {
          throw InvalidSurveyResponseViolation(
            reason: 'question "${question.id}" requires a booleanValue',
          );
        }
    }
  }
}
