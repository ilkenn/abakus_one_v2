import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/crm/application/identity/survey_id_generator.dart';
import 'package:abakus_one_v2/features/crm/application/use_cases/create_survey.dart';
import 'package:abakus_one_v2/features/crm/data/survey_repository.dart';
import 'package:abakus_one_v2/features/crm/domain/surveys/survey_question.dart';
import 'package:abakus_one_v2/features/crm/domain/surveys/survey_question_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/crm_test_fixtures.dart';

void main() {
  group('CreateSurvey', () {
    CreateSurvey buildUseCase({required SurveyRepository repository}) {
      return CreateSurvey(
        authorizationPolicy: const AllowAllCrmPolicy(),
        idGenerator: SequentialSurveyIdGenerator(),
        repository: repository,
      );
    }

    test('creates a survey with a rating question', () async {
      final repository = InMemorySurveyRepository();
      final useCase = buildUseCase(repository: repository);

      final survey = await useCase(
        title: 'Memnuniyet Anketi',
        questions: const [
          SurveyQuestion(
            id: 'q1',
            type: SurveyQuestionType.rating,
            prompt: 'Deneyiminizi puanlayın',
          ),
        ],
        activeFrom: DateTime(2026, 1, 1),
        performedByStaffId: 'manager-1',
        createdAt: DateTime(2026, 1, 1),
      );

      expect(survey.questions, hasLength(1));
      expect(await repository.findById(survey.id), survey);
    });

    test('rejects a survey with no questions', () async {
      final useCase = buildUseCase(repository: InMemorySurveyRepository());

      expect(
        () => useCase(
          title: 'Boş Anket',
          questions: const [],
          activeFrom: DateTime(2026, 1, 1),
          performedByStaffId: 'manager-1',
          createdAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<InvalidSurveyViolation>()),
      );
    });

    test('rejects a multipleChoice question with fewer than 2 options',
        () async {
      final useCase = buildUseCase(repository: InMemorySurveyRepository());

      expect(
        () => useCase(
          title: 'Anket',
          questions: const [
            SurveyQuestion(
              id: 'q1',
              type: SurveyQuestionType.multipleChoice,
              prompt: 'Hangisi?',
              options: [SurveyQuestionOption(id: 'a', label: 'A')],
            ),
          ],
          activeFrom: DateTime(2026, 1, 1),
          performedByStaffId: 'manager-1',
          createdAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<InvalidSurveyViolation>()),
      );
    });

    test('rejects duplicate question ids', () async {
      final useCase = buildUseCase(repository: InMemorySurveyRepository());

      expect(
        () => useCase(
          title: 'Anket',
          questions: const [
            SurveyQuestion(
              id: 'q1',
              type: SurveyQuestionType.boolean,
              prompt: 'Tekrar gelir misiniz?',
            ),
            SurveyQuestion(
              id: 'q1',
              type: SurveyQuestionType.text,
              prompt: 'Yorumunuz?',
            ),
          ],
          activeFrom: DateTime(2026, 1, 1),
          performedByStaffId: 'manager-1',
          createdAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<InvalidSurveyViolation>()),
      );
    });

    test('an unauthorized actor cannot create a survey', () async {
      final useCase = CreateSurvey(
        authorizationPolicy: const DenyAllCrmPolicy(),
        idGenerator: SequentialSurveyIdGenerator(),
        repository: InMemorySurveyRepository(),
      );

      expect(
        () => useCase(
          title: 'Anket',
          questions: const [
            SurveyQuestion(
              id: 'q1',
              type: SurveyQuestionType.boolean,
              prompt: 'Tekrar gelir misiniz?',
            ),
          ],
          activeFrom: DateTime(2026, 1, 1),
          performedByStaffId: 'staff-1',
          createdAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
