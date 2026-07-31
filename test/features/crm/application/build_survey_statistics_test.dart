import 'package:abakus_one_v2/features/crm/application/use_cases/build_survey_statistics.dart';
import 'package:abakus_one_v2/features/crm/data/survey_repository.dart';
import 'package:abakus_one_v2/features/crm/data/survey_response_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/surveys/survey.dart';
import 'package:abakus_one_v2/features/crm/domain/surveys/survey_answer.dart';
import 'package:abakus_one_v2/features/crm/domain/surveys/survey_question.dart';
import 'package:abakus_one_v2/features/crm/domain/surveys/survey_question_type.dart';
import 'package:abakus_one_v2/features/crm/domain/surveys/survey_response.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

Survey _buildSurvey() {
  return Survey(
    id: 'survey-1',
    title: 'Memnuniyet Anketi',
    questions: const [
      SurveyQuestion(
        id: 'q-rating',
        type: SurveyQuestionType.rating,
        prompt: 'Puanınız?',
      ),
      SurveyQuestion(
        id: 'q-choice',
        type: SurveyQuestionType.multipleChoice,
        prompt: 'Hangisi?',
        options: [
          SurveyQuestionOption(id: 'a', label: 'A'),
          SurveyQuestionOption(id: 'b', label: 'B'),
        ],
      ),
      SurveyQuestion(
        id: 'q-bool',
        type: SurveyQuestionType.boolean,
        prompt: 'Tekrar gelir misiniz?',
      ),
    ],
    activeFrom: DateTime(2026, 1, 1),
    createdByStaffId: 'manager-1',
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

SurveyResponse _response({
  required String id,
  required int rating,
  required String choice,
  required bool boolAnswer,
}) {
  return SurveyResponse(
    id: id,
    surveyId: 'survey-1',
    customerId: 'customer-$id',
    answers: [
      SurveyAnswer(questionId: 'q-rating', numericValue: rating),
      SurveyAnswer(questionId: 'q-choice', selectedOptionIds: [choice]),
      SurveyAnswer(questionId: 'q-bool', booleanValue: boolAnswer),
    ],
    submittedAt: DateTime(2026, 1, 5),
  );
}

void main() {
  group('BuildSurveyStatistics', () {
    test('aggregates numeric average, option counts, and boolean counts',
        () async {
      final surveyRepository = InMemorySurveyRepository();
      await surveyRepository.save(_buildSurvey());
      final responseRepository = InMemorySurveyResponseRepository();
      await responseRepository.append(
          _response(id: 'r1', rating: 5, choice: 'a', boolAnswer: true));
      await responseRepository.append(
          _response(id: 'r2', rating: 3, choice: 'a', boolAnswer: false));
      await responseRepository.append(
          _response(id: 'r3', rating: 4, choice: 'b', boolAnswer: true));

      final useCase = BuildSurveyStatistics(
        clock: FakeClock(DateTime(2026, 1, 10)),
        surveyRepository: surveyRepository,
        responseRepository: responseRepository,
      );

      final stats = await useCase(surveyId: 'survey-1');

      expect(stats.totalResponses, 3);

      final ratingStats = stats.questionStatistics
          .firstWhere((q) => q.questionId == 'q-rating');
      expect(ratingStats.averageNumericValue, closeTo(4.0, 0.001));

      final choiceStats = stats.questionStatistics
          .firstWhere((q) => q.questionId == 'q-choice');
      expect(choiceStats.optionCounts, {'a': 2, 'b': 1});

      final boolStats =
          stats.questionStatistics.firstWhere((q) => q.questionId == 'q-bool');
      expect(boolStats.booleanTrueCount, 2);
      expect(boolStats.booleanFalseCount, 1);
    });

    test('a multipleChoice option with zero votes is still present at 0',
        () async {
      final surveyRepository = InMemorySurveyRepository();
      await surveyRepository.save(_buildSurvey());
      final responseRepository = InMemorySurveyResponseRepository();
      await responseRepository.append(
          _response(id: 'r1', rating: 5, choice: 'a', boolAnswer: true));

      final useCase = BuildSurveyStatistics(
        clock: FakeClock(DateTime(2026, 1, 10)),
        surveyRepository: surveyRepository,
        responseRepository: responseRepository,
      );

      final stats = await useCase(surveyId: 'survey-1');
      final choiceStats = stats.questionStatistics
          .firstWhere((q) => q.questionId == 'q-choice');

      expect(choiceStats.optionCounts['b'], 0);
    });

    test('no responses yields zeroed statistics, never a crash', () async {
      final surveyRepository = InMemorySurveyRepository();
      await surveyRepository.save(_buildSurvey());

      final useCase = BuildSurveyStatistics(
        clock: FakeClock(DateTime(2026, 1, 10)),
        surveyRepository: surveyRepository,
        responseRepository: InMemorySurveyResponseRepository(),
      );

      final stats = await useCase(surveyId: 'survey-1');

      expect(stats.totalResponses, 0);
      for (final q in stats.questionStatistics) {
        expect(q.responseCount, 0);
      }
    });
  });
}
