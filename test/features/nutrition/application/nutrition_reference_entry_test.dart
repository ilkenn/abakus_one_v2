import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/inventory/domain/inventory_unit.dart';
import 'package:abakus_one_v2/features/nutrition/application/identity/nutrition_reference_entry_id_generator.dart';
import 'package:abakus_one_v2/features/nutrition/application/use_cases/review_nutrition_reference_entry.dart';
import 'package:abakus_one_v2/features/nutrition/application/use_cases/set_nutrition_reference_entry.dart';
import 'package:abakus_one_v2/features/nutrition/data/nutrition_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/nutrition/data/nutrition_reference_entry_repository.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_confidence.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_data_source_type.dart';
import 'package:abakus_one_v2/features/nutrition/domain/nutrition_value_set.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/nutrition_test_fixtures.dart';

void main() {
  group('SetNutritionReferenceEntry', () {
    test('a manual entry with a reason is stored at low confidence', () async {
      final repository = InMemoryNutritionReferenceEntryRepository();
      final useCase = SetNutritionReferenceEntry(
        authorizationPolicy: const AllowAllNutritionPolicy(),
        idGenerator: SequentialNutritionReferenceEntryIdGenerator(),
        repository: repository,
        auditRepository: InMemoryNutritionAuditEntryRepository(),
      );

      final entry = await useCase(
        organizationId: 'org-1',
        ingredientId: 'ingredient-chicken',
        values:
            const NutritionValueSet(energyKcal: 165, proteinMilligrams: 31000),
        referenceUnit: InventoryUnit.gram,
        sourceType: NutritionDataSourceType.manual,
        overrideReason: 'Paketten okundu',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(entry.confidence, NutritionConfidence.low);
      expect(entry.isManuallyOverridden, isTrue);
      expect(entry.values.isComplete, isFalse);
    });

    test('a manual entry without a reason throws', () async {
      final useCase = SetNutritionReferenceEntry(
        authorizationPolicy: const AllowAllNutritionPolicy(),
        idGenerator: SequentialNutritionReferenceEntryIdGenerator(),
        repository: InMemoryNutritionReferenceEntryRepository(),
        auditRepository: InMemoryNutritionAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          ingredientId: 'ingredient-chicken',
          values: const NutritionValueSet(energyKcal: 165),
          referenceUnit: InventoryUnit.gram,
          sourceType: NutritionDataSourceType.manual,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<NutritionOverrideReasonRequiredViolation>()),
      );
    });

    test('a second call for the same ingredient upserts (same id)', () async {
      final repository = InMemoryNutritionReferenceEntryRepository();
      final useCase = SetNutritionReferenceEntry(
        authorizationPolicy: const AllowAllNutritionPolicy(),
        idGenerator: SequentialNutritionReferenceEntryIdGenerator(),
        repository: repository,
        auditRepository: InMemoryNutritionAuditEntryRepository(),
      );

      final first = await useCase(
        organizationId: 'org-1',
        ingredientId: 'ingredient-chicken',
        values: const NutritionValueSet(energyKcal: 165),
        referenceUnit: InventoryUnit.gram,
        sourceType: NutritionDataSourceType.manual,
        overrideReason: 'İlk giriş',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );
      final second = await useCase(
        organizationId: 'org-1',
        ingredientId: 'ingredient-chicken',
        values: const NutritionValueSet(energyKcal: 170),
        referenceUnit: InventoryUnit.gram,
        sourceType: NutritionDataSourceType.manual,
        overrideReason: 'Düzeltme',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(second.id, first.id);
      expect(second.revision, 2);
      final all = await repository.findByOrganizationId('org-1');
      expect(all, hasLength(1));
    });

    test('an external-provider entry defaults to medium confidence', () async {
      final useCase = SetNutritionReferenceEntry(
        authorizationPolicy: const AllowAllNutritionPolicy(),
        idGenerator: SequentialNutritionReferenceEntryIdGenerator(),
        repository: InMemoryNutritionReferenceEntryRepository(),
        auditRepository: InMemoryNutritionAuditEntryRepository(),
      );

      final entry = await useCase(
        organizationId: 'org-1',
        ingredientId: 'ingredient-rice',
        values: const NutritionValueSet(energyKcal: 130),
        referenceUnit: InventoryUnit.gram,
        sourceType: NutritionDataSourceType.externalProvider,
        sourceName: 'USDA FoodData Central',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(entry.confidence, NutritionConfidence.medium);
      expect(entry.isManuallyOverridden, isFalse);
    });

    test('an unauthorized actor is denied', () async {
      final useCase = SetNutritionReferenceEntry(
        authorizationPolicy: const DenyAllNutritionPolicy(),
        idGenerator: SequentialNutritionReferenceEntryIdGenerator(),
        repository: InMemoryNutritionReferenceEntryRepository(),
        auditRepository: InMemoryNutritionAuditEntryRepository(),
      );

      expect(
        () => useCase(
          organizationId: 'org-1',
          ingredientId: 'ingredient-chicken',
          values: const NutritionValueSet(energyKcal: 165),
          referenceUnit: InventoryUnit.gram,
          sourceType: NutritionDataSourceType.externalProvider,
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('ReviewNutritionReferenceEntry', () {
    test('raises confidence and records reviewer', () async {
      final repository = InMemoryNutritionReferenceEntryRepository();
      final setEntry = SetNutritionReferenceEntry(
        authorizationPolicy: const AllowAllNutritionPolicy(),
        idGenerator: SequentialNutritionReferenceEntryIdGenerator(),
        repository: repository,
        auditRepository: InMemoryNutritionAuditEntryRepository(),
      );
      final entry = await setEntry(
        organizationId: 'org-1',
        ingredientId: 'ingredient-chicken',
        values: const NutritionValueSet(energyKcal: 165),
        referenceUnit: InventoryUnit.gram,
        sourceType: NutritionDataSourceType.manual,
        overrideReason: 'Paketten okundu',
        performedByStaffId: 'staff-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final useCase = ReviewNutritionReferenceEntry(
        authorizationPolicy: const AllowAllNutritionPolicy(),
        repository: repository,
        auditRepository: InMemoryNutritionAuditEntryRepository(),
      );
      final reviewed = await useCase(
        entryId: entry.id,
        confidence: NutritionConfidence.high,
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(reviewed.confidence, NutritionConfidence.high);
      expect(reviewed.reviewedByStaffId, 'manager-1');
    });

    test('an unknown entry throws', () async {
      final useCase = ReviewNutritionReferenceEntry(
        authorizationPolicy: const AllowAllNutritionPolicy(),
        repository: InMemoryNutritionReferenceEntryRepository(),
        auditRepository: InMemoryNutritionAuditEntryRepository(),
      );

      expect(
        () => useCase(
          entryId: 'missing',
          confidence: NutritionConfidence.high,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownNutritionEntityViolation>()),
      );
    });
  });
}
