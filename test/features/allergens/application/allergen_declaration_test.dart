import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/allergens/application/identity/ingredient_allergen_declaration_id_generator.dart';
import 'package:abakus_one_v2/features/allergens/application/use_cases/confirm_ingredient_allergen_declaration.dart';
import 'package:abakus_one_v2/features/allergens/application/use_cases/get_allergen_review_queue.dart';
import 'package:abakus_one_v2/features/allergens/application/use_cases/set_ingredient_allergen_declaration.dart';
import 'package:abakus_one_v2/features/allergens/data/allergen_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/allergens/data/ingredient_allergen_declaration_repository.dart';
import 'package:abakus_one_v2/features/allergens/domain/allergen_confidence.dart';
import 'package:abakus_one_v2/features/allergens/domain/allergen_declaration_status.dart';
import 'package:abakus_one_v2/features/allergens/domain/allergen_source_type.dart';
import 'package:abakus_one_v2/features/allergens/domain/allergen_type.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/allergen_test_fixtures.dart';

void main() {
  group('SetIngredientAllergenDeclaration', () {
    test(
        'a manual declaration with a reason is stored at high confidence '
        'and confirmed', () async {
      final repository = InMemoryIngredientAllergenDeclarationRepository();
      final useCase = SetIngredientAllergenDeclaration(
        authorizationPolicy: const AllowAllAllergensPolicy(),
        idGenerator: SequentialIngredientAllergenDeclarationIdGenerator(),
        repository: repository,
        auditRepository: InMemoryAllergenAuditEntryRepository(),
      );

      final declaration = await useCase(
        organizationId: 'org-1',
        ingredientId: 'ingredient-bread',
        allergenType: AllergenType.gluten,
        status: AllergenDeclarationStatus.contains,
        sourceType: AllergenSourceType.manual,
        reason: 'Ambalajda belirtilmiş',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(declaration.confidence, AllergenConfidence.high);
      expect(declaration.isConfirmedByHuman, isTrue);
    });

    test('a manual declaration without a reason throws', () async {
      final useCase = SetIngredientAllergenDeclaration(
        authorizationPolicy: const AllowAllAllergensPolicy(),
        idGenerator: SequentialIngredientAllergenDeclarationIdGenerator(),
        repository: InMemoryIngredientAllergenDeclarationRepository(),
        auditRepository: InMemoryAllergenAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          ingredientId: 'ingredient-bread',
          allergenType: AllergenType.gluten,
          status: AllergenDeclarationStatus.contains,
          sourceType: AllergenSourceType.manual,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AllergenOverrideReasonRequiredViolation>()),
      );
    });

    test(
        'an AI-suggested declaration is always unconfirmed, regardless of '
        'caller intent', () async {
      final useCase = SetIngredientAllergenDeclaration(
        authorizationPolicy: const AllowAllAllergensPolicy(),
        idGenerator: SequentialIngredientAllergenDeclarationIdGenerator(),
        repository: InMemoryIngredientAllergenDeclarationRepository(),
        auditRepository: InMemoryAllergenAuditEntryRepository(),
      );

      final declaration = await useCase(
        organizationId: 'org-1',
        ingredientId: 'ingredient-sauce',
        allergenType: AllergenType.soy,
        status: AllergenDeclarationStatus.mayContain,
        sourceType: AllergenSourceType.aiSuggested,
        confidence: AllergenConfidence.high,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(declaration.isConfirmedByHuman, isFalse);
    });

    test('a second call for the same ingredient+allergen upserts', () async {
      final repository = InMemoryIngredientAllergenDeclarationRepository();
      final useCase = SetIngredientAllergenDeclaration(
        authorizationPolicy: const AllowAllAllergensPolicy(),
        idGenerator: SequentialIngredientAllergenDeclarationIdGenerator(),
        repository: repository,
        auditRepository: InMemoryAllergenAuditEntryRepository(),
      );

      final first = await useCase(
        organizationId: 'org-1',
        ingredientId: 'ingredient-bread',
        allergenType: AllergenType.gluten,
        status: AllergenDeclarationStatus.unknown,
        sourceType: AllergenSourceType.manual,
        reason: 'İlk giriş',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );
      final second = await useCase(
        organizationId: 'org-1',
        ingredientId: 'ingredient-bread',
        allergenType: AllergenType.gluten,
        status: AllergenDeclarationStatus.contains,
        sourceType: AllergenSourceType.manual,
        reason: 'Doğrulandı',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(second.id, first.id);
      expect(second.revision, 2);
      final byIngredient =
          await repository.findByIngredientId('ingredient-bread');
      expect(byIngredient, hasLength(1));
    });

    test('an unauthorized actor is denied', () async {
      final useCase = SetIngredientAllergenDeclaration(
        authorizationPolicy: const DenyAllAllergensPolicy(),
        idGenerator: SequentialIngredientAllergenDeclarationIdGenerator(),
        repository: InMemoryIngredientAllergenDeclarationRepository(),
        auditRepository: InMemoryAllergenAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          ingredientId: 'ingredient-bread',
          allergenType: AllergenType.gluten,
          status: AllergenDeclarationStatus.contains,
          sourceType: AllergenSourceType.aiSuggested,
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('ConfirmIngredientAllergenDeclaration', () {
    test('confirms an AI suggestion and records the reviewer', () async {
      final repository = InMemoryIngredientAllergenDeclarationRepository();
      final setDeclaration = SetIngredientAllergenDeclaration(
        authorizationPolicy: const AllowAllAllergensPolicy(),
        idGenerator: SequentialIngredientAllergenDeclarationIdGenerator(),
        repository: repository,
        auditRepository: InMemoryAllergenAuditEntryRepository(),
      );
      final declaration = await setDeclaration(
        organizationId: 'org-1',
        ingredientId: 'ingredient-sauce',
        allergenType: AllergenType.soy,
        status: AllergenDeclarationStatus.mayContain,
        sourceType: AllergenSourceType.aiSuggested,
        performedByStaffId: 'system',
        performedAt: DateTime(2026, 1, 1),
      );
      expect(declaration.isConfirmedByHuman, isFalse);

      final useCase = ConfirmIngredientAllergenDeclaration(
        authorizationPolicy: const AllowAllAllergensPolicy(),
        repository: repository,
        auditRepository: InMemoryAllergenAuditEntryRepository(),
      );
      final confirmed = await useCase(
        declarationId: declaration.id,
        confidence: AllergenConfidence.high,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(confirmed.isConfirmedByHuman, isTrue);
      expect(confirmed.reviewedByStaffId, 'manager-1');
      expect(confirmed.confidence, AllergenConfidence.high);
    });

    test('an unknown declaration throws', () async {
      final useCase = ConfirmIngredientAllergenDeclaration(
        authorizationPolicy: const AllowAllAllergensPolicy(),
        repository: InMemoryIngredientAllergenDeclarationRepository(),
        auditRepository: InMemoryAllergenAuditEntryRepository(),
      );

      expect(
        () => useCase(
          declarationId: 'missing',
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownAllergenEntityViolation>()),
      );
    });
  });

  group('GetAllergenReviewQueue', () {
    test(
        'surfaces unconfirmed AI suggestions, unknown status, and '
        'low/unknown confidence, and excludes a confirmed high-confidence '
        'manual one', () async {
      final repository = InMemoryIngredientAllergenDeclarationRepository();
      final setDeclaration = SetIngredientAllergenDeclaration(
        authorizationPolicy: const AllowAllAllergensPolicy(),
        idGenerator: SequentialIngredientAllergenDeclarationIdGenerator(),
        repository: repository,
        auditRepository: InMemoryAllergenAuditEntryRepository(),
      );

      // 1. Unconfirmed AI suggestion -> in queue.
      await setDeclaration(
        organizationId: 'org-1',
        ingredientId: 'ingredient-a',
        allergenType: AllergenType.soy,
        status: AllergenDeclarationStatus.mayContain,
        sourceType: AllergenSourceType.aiSuggested,
        performedByStaffId: 'system',
        performedAt: DateTime(2026, 1, 1),
      );
      // 2. Unknown status -> in queue.
      await setDeclaration(
        organizationId: 'org-1',
        ingredientId: 'ingredient-b',
        allergenType: AllergenType.egg,
        status: AllergenDeclarationStatus.unknown,
        sourceType: AllergenSourceType.manual,
        reason: 'Bilinmiyor',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );
      // 3. Confirmed, high-confidence manual entry -> NOT in queue.
      await setDeclaration(
        organizationId: 'org-1',
        ingredientId: 'ingredient-c',
        allergenType: AllergenType.milk,
        status: AllergenDeclarationStatus.explicitlyFreeFrom,
        sourceType: AllergenSourceType.manual,
        reason: 'Laboratuvar testi',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final useCase = GetAllergenReviewQueue(
        authorizationPolicy: const AllowAllAllergensPolicy(),
        repository: repository,
      );
      final queue = await useCase(
        organizationId: 'org-1',
        performedByStaffId: 'manager-1',
      );

      final ingredientIds = queue.map((d) => d.ingredientId).toSet();
      expect(ingredientIds, {'ingredient-a', 'ingredient-b'});
      expect(ingredientIds.contains('ingredient-c'), isFalse);
    });
  });
}
