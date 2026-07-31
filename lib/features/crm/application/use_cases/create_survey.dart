import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/survey_repository.dart';
import '../../domain/segmentation/customer_category.dart';
import '../../domain/surveys/survey.dart';
import '../../domain/surveys/survey_question.dart';
import '../../domain/surveys/survey_question_type.dart';
import '../identity/survey_id_generator.dart';

/// An administrator authors a new [Survey] — manager-only
/// ([PosAuthorizedAction.manageSurveys]). Validates the question set
/// itself is coherent (non-empty, unique question ids, every
/// [SurveyQuestionType.multipleChoice] question has at least 2 options)
/// before anything is persisted.
class CreateSurvey {
  const CreateSurvey({
    required PosAuthorizationPolicy authorizationPolicy,
    required SurveyIdGenerator idGenerator,
    required SurveyRepository repository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final SurveyIdGenerator _idGenerator;
  final SurveyRepository _repository;

  Future<Survey> call({
    required String title,
    required List<SurveyQuestion> questions,
    CustomerCategory? targetCategory,
    String? optionalRewardRuleId,
    required DateTime activeFrom,
    DateTime? activeUntil,
    bool isActive = true,
    required String performedByStaffId,
    required DateTime createdAt,
  }) async {
    const action = PosAuthorizedAction.manageSurveys;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    if (questions.isEmpty) {
      throw const InvalidSurveyViolation(
          reason: 'at least one question is required');
    }
    final questionIds = questions.map((q) => q.id).toSet();
    if (questionIds.length != questions.length) {
      throw const InvalidSurveyViolation(reason: 'question ids must be unique');
    }
    for (final question in questions) {
      if (question.type == SurveyQuestionType.multipleChoice &&
          question.options.length < 2) {
        throw InvalidSurveyViolation(
          reason: 'multipleChoice question "${question.id}" needs at '
              'least 2 options',
        );
      }
    }

    final survey = Survey(
      id: _idGenerator.nextSurveyId(),
      title: title,
      questions: questions,
      targetCategory: targetCategory,
      optionalRewardRuleId: optionalRewardRuleId,
      activeFrom: activeFrom,
      activeUntil: activeUntil,
      isActive: isActive,
      createdByStaffId: performedByStaffId,
      createdAt: createdAt,
      revision: 1,
    );
    await _repository.save(survey);
    return survey;
  }
}
