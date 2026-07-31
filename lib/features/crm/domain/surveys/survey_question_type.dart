/// The kind of question a [SurveyQuestion] asks — Sprint 5D's Survey
/// Engine. [rating]/[stars]/[emoji] all answer through the same
/// `SurveyAnswer.numericValue` scale — the type only changes how a
/// screen renders that scale (a number, a star row, an emoji face), never
/// how it's stored or aggregated.
enum SurveyQuestionType {
  rating,
  stars,
  emoji,
  multipleChoice,
  text,
  boolean,
}
