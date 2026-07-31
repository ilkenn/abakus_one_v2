import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/crm/application/identity/survey_response_id_generator.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/submit_survey_response.dart';
import 'package:abakus_one_v2/features/crm/data/survey_repository.dart';
import 'package:abakus_one_v2/features/crm/data/survey_response_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/surveys/survey.dart';
import 'package:abakus_one_v2/features/crm/domain/surveys/survey_answer.dart';
import 'package:abakus_one_v2/features/crm/domain/surveys/survey_question.dart';
import 'package:abakus_one_v2/features/crm/domain/surveys/survey_question_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../pos/test_support/fake_clock.dart';

Survey _buildSurvey({bool isActive = true}) {
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
        id: 'q-text',
        type: SurveyQuestionType.text,
        prompt: 'Yorumunuz?',
      ),
      SurveyQuestion(
        id: 'q-bool',
        type: SurveyQuestionType.boolean,
        prompt: 'Tekrar gelir misiniz?',
      ),
    ],
    isActive: isActive,
    activeFrom: DateTime(2026, 1, 1),
    createdByStaffId: 'manager-1',
    createdAt: DateTime(2026, 1, 1),
    revision: 1,
  );
}

const _validAnswers = [
  SurveyAnswer(questionId: 'q-rating', numericValue: 4),
  SurveyAnswer(questionId: 'q-choice', selectedOptionIds: ['a']),
  SurveyAnswer(questionId: 'q-text', textValue: 'Harika!'),
  SurveyAnswer(questionId: 'q-bool', booleanValue: true),
];

void main() {
  final now = DateTime(2026, 1, 5);

  group('SubmitSurveyResponse', () {
    SubmitSurveyResponse buildUseCase({
      required SurveyRepository surveyRepository,
      required SurveyResponseRepository responseRepository,
    }) {
      return SubmitSurveyResponse(
        clock: FakeClock(now),
        idGenerator: SequentialSurveyResponseIdGenerator(),
        surveyRepository: surveyRepository,
        responseRepository: responseRepository,
      );
    }

    test('accepts a fully and validly answered response', () async {
      final surveyRepository = InMemorySurveyRepository();
      await surveyRepository.save(_buildSurvey());
      final responseRepository = InMemorySurveyResponseRepository();
      final useCase = buildUseCase(
        surveyRepository: surveyRepository,
        responseRepository: responseRepository,
      );

      final response = await useCase(
        surveyId: 'survey-1',
        customerId: 'customer-1',
        answers: _validAnswers,
      );

      expect(response.answers, hasLength(4));
      expect(
        await responseRepository.findBySurveyId('survey-1'),
        [response],
      );
    });

    test('an unknown survey id throws UnknownCrmEntityViolation', () async {
      final useCase = buildUseCase(
        surveyRepository: InMemorySurveyRepository(),
        responseRepository: InMemorySurveyResponseRepository(),
      );

      expect(
        () => useCase(
          surveyId: 'missing',
          customerId: 'customer-1',
          answers: _validAnswers,
        ),
        throwsA(isA<UnknownCrmEntityViolation>()),
      );
    });

    test('an inactive survey rejects a submission', () async {
      final surveyRepository = InMemorySurveyRepository();
      await surveyRepository.save(_buildSurvey(isActive: false));
      final useCase = buildUseCase(
        surveyRepository: surveyRepository,
        responseRepository: InMemorySurveyResponseRepository(),
      );

      expect(
        () => useCase(
          surveyId: 'survey-1',
          customerId: 'customer-1',
          answers: _validAnswers,
        ),
        throwsA(isA<InvalidSurveyResponseViolation>()),
      );
    });

    test('a missing answer rejects the submission', () async {
      final surveyRepository = InMemorySurveyRepository();
      await surveyRepository.save(_buildSurvey());
      final useCase = buildUseCase(
        surveyRepository: surveyRepository,
        responseRepository: InMemorySurveyResponseRepository(),
      );

      expect(
        () => useCase(
          surveyId: 'survey-1',
          customerId: 'customer-1',
          answers: _validAnswers.sublist(0, 3),
        ),
        throwsA(isA<InvalidSurveyResponseViolation>()),
      );
    });

    test('an out-of-range rating value is rejected', () async {
      final surveyRepository = InMemorySurveyRepository();
      await surveyRepository.save(_buildSurvey());
      final useCase = buildUseCase(
        surveyRepository: surveyRepository,
        responseRepository: InMemorySurveyResponseRepository(),
      );

      final answers = [
        const SurveyAnswer(questionId: 'q-rating', numericValue: 99),
        _validAnswers[1],
        _validAnswers[2],
        _validAnswers[3],
      ];

      expect(
        () => useCase(
          surveyId: 'survey-1',
          customerId: 'customer-1',
          answers: answers,
        ),
        throwsA(isA<InvalidSurveyResponseViolation>()),
      );
    });

    test('an unknown multipleChoice option id is rejected', () async {
      final surveyRepository = InMemorySurveyRepository();
      await surveyRepository.save(_buildSurvey());
      final useCase = buildUseCase(
        surveyRepository: surveyRepository,
        responseRepository: InMemorySurveyResponseRepository(),
      );

      final answers = [
        _validAnswers[0],
        const SurveyAnswer(
            questionId: 'q-choice', selectedOptionIds: ['unknown']),
        _validAnswers[2],
        _validAnswers[3],
      ];

      expect(
        () => useCase(
          surveyId: 'survey-1',
          customerId: 'customer-1',
          answers: answers,
        ),
        throwsA(isA<InvalidSurveyResponseViolation>()),
      );
    });
  });
}
