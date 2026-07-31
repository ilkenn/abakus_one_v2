/// One question's aggregated response distribution — Sprint 5D's Survey
/// Engine. Which field is populated depends on the question's
/// `SurveyQuestionType`, mirroring `SurveyAnswer`'s own per-type shape:
/// [averageNumericValue] for `rating`/`stars`/`emoji`, [optionCounts] for
/// `multipleChoice`, [booleanTrueCount]/[booleanFalseCount] for
/// `boolean`. `text` answers are counted in [responseCount] only — free
/// text is never aggregated into a false "distribution."
class SurveyQuestionStatistics {
  const SurveyQuestionStatistics({
    required this.questionId,
    required this.responseCount,
    this.averageNumericValue,
    this.optionCounts = const {},
    this.booleanTrueCount,
    this.booleanFalseCount,
  });

  final String questionId;
  final int responseCount;
  final double? averageNumericValue;

  /// Option id → selection count. Every configured option is present
  /// (possibly at `0`), never omitted just because it got no votes.
  final Map<String, int> optionCounts;

  final int? booleanTrueCount;
  final int? booleanFalseCount;
}

/// A [Survey]'s assembled statistics — computed fresh on every read by
/// `BuildSurveyStatistics`, never persisted itself.
class SurveyStatistics {
  const SurveyStatistics({
    required this.surveyId,
    required this.totalResponses,
    required this.questionStatistics,
    required this.generatedAt,
  });

  final String surveyId;
  final int totalResponses;
  final List<SurveyQuestionStatistics> questionStatistics;
  final DateTime generatedAt;
}
