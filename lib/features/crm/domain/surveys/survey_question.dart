import 'survey_question_type.dart';

/// One option a [SurveyQuestionType.multipleChoice] question offers.
class SurveyQuestionOption {
  const SurveyQuestionOption({required this.id, required this.label});

  final String id;
  final String label;
}

/// One question within a [Survey]. [options] is only meaningful when
/// [type] is [SurveyQuestionType.multipleChoice] — empty for every other
/// type.
class SurveyQuestion {
  const SurveyQuestion({
    required this.id,
    required this.type,
    required this.prompt,
    this.options = const [],
  });

  final String id;
  final SurveyQuestionType type;
  final String prompt;
  final List<SurveyQuestionOption> options;
}
