/// One answer within a [SurveyResponse], for one [SurveyQuestion]. Which
/// field is meaningful depends on that question's `SurveyQuestionType`:
/// [SurveyQuestionType.rating]/`.stars`/`.emoji` → [numericValue],
/// [SurveyQuestionType.multipleChoice] → [selectedOptionIds],
/// [SurveyQuestionType.text] → [textValue],
/// [SurveyQuestionType.boolean] → [booleanValue].
class SurveyAnswer {
  const SurveyAnswer({
    required this.questionId,
    this.numericValue,
    this.selectedOptionIds = const [],
    this.textValue,
    this.booleanValue,
  });

  final String questionId;
  final int? numericValue;
  final List<String> selectedOptionIds;
  final String? textValue;
  final bool? booleanValue;
}
