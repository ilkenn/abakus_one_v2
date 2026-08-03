import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/restaurant_setup/application/identity/setup_template_application_snapshot_id_generator.dart';
import 'package:abakus_one_v2/features/restaurant_setup/application/identity/setup_template_id_generator.dart';
import 'package:abakus_one_v2/features/restaurant_setup/application/use_cases/apply_setup_template.dart';
import 'package:abakus_one_v2/features/restaurant_setup/application/use_cases/create_setup_template.dart';
import 'package:abakus_one_v2/features/restaurant_setup/data/setup_template_application_snapshot_repository.dart';
import 'package:abakus_one_v2/features/restaurant_setup/data/setup_template_repository.dart';
import 'package:abakus_one_v2/features/restaurant_setup/domain/setup_template.dart';
import 'package:abakus_one_v2/features/restaurant_setup/domain/setup_template_category.dart';
import 'package:abakus_one_v2/features/restaurant_setup/domain/setup_template_content.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/restaurant_setup_test_fixtures.dart';

void main() {
  group('CreateSetupTemplate', () {
    test('a public template must have no owner organization', () async {
      final useCase = CreateSetupTemplate(
        authorizationPolicy: const AllowAllSetupPolicy(),
        idGenerator: SequentialSetupTemplateIdGenerator(),
        repository: InMemorySetupTemplateRepository(),
      );

      expect(
        () => useCase(
          category: SetupTemplateCategory.burger,
          name: 'Burger Şablonu',
          isPublic: true,
          ownerOrganizationId: 'org-1',
          performedByStaffId: 'admin-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<InvalidSetupTemplateOwnershipViolation>()),
      );
    });

    test('a private template must have an owner organization', () async {
      final useCase = CreateSetupTemplate(
        authorizationPolicy: const AllowAllSetupPolicy(),
        idGenerator: SequentialSetupTemplateIdGenerator(),
        repository: InMemorySetupTemplateRepository(),
      );

      expect(
        () => useCase(
          category: SetupTemplateCategory.burger,
          name: 'Özel Şablon',
          isPublic: false,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<InvalidSetupTemplateOwnershipViolation>()),
      );
    });

    test('a private template is created for the owning organization', () async {
      final repository = InMemorySetupTemplateRepository();
      final useCase = CreateSetupTemplate(
        authorizationPolicy: const AllowAllSetupPolicy(),
        idGenerator: SequentialSetupTemplateIdGenerator(),
        repository: repository,
      );

      final template = await useCase(
        category: SetupTemplateCategory.burger,
        name: 'Abaküs Özel Reçetesi',
        isPublic: false,
        ownerOrganizationId: 'org-1',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(template.isPublic, isFalse);
      final visibleToOwner = await repository.findVisibleTo('org-1');
      final visibleToOther = await repository.findVisibleTo('org-2');
      expect(visibleToOwner, contains(template));
      expect(visibleToOther, isNot(contains(template)));
    });

    test('an unauthorized actor cannot create a public template', () async {
      final useCase = CreateSetupTemplate(
        authorizationPolicy: const DenyAllSetupPolicy(),
        idGenerator: SequentialSetupTemplateIdGenerator(),
        repository: InMemorySetupTemplateRepository(),
      );

      expect(
        () => useCase(
          category: SetupTemplateCategory.burger,
          name: 'Genel Şablon',
          isPublic: true,
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });

  group('ApplySetupTemplate', () {
    test('creates a frozen snapshot, never mutates the template', () async {
      final templateRepository = InMemorySetupTemplateRepository(seed: [
        SetupTemplate(
          id: 'template-1',
          category: SetupTemplateCategory.bowlAndSalad,
          name: 'Bowl Şablonu',
          categorySuggestions: const [
            TemplateCategorySuggestion(tempId: 't1', name: 'Bowl'),
          ],
          isPublic: true,
          createdAt: DateTime(2026, 1, 1),
          revision: 3,
        ),
      ]);
      final snapshotRepository =
          InMemorySetupTemplateApplicationSnapshotRepository();
      final useCase = ApplySetupTemplate(
        authorizationPolicy: const AllowAllSetupPolicy(),
        templateRepository: templateRepository,
        snapshotRepository: snapshotRepository,
        idGenerator: SequentialSetupTemplateApplicationSnapshotIdGenerator(),
      );

      final snapshot = await useCase(
        templateId: 'template-1',
        organizationId: 'org-1',
        restaurantId: 'restaurant-1',
        branchId: 'branch-1',
        performedByStaffId: 'manager-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(snapshot.templateRevisionApplied, 3);
      expect(snapshot.categorySuggestions, hasLength(1));

      final stored = await snapshotRepository.findByBranchId('branch-1');
      expect(stored, hasLength(1));

      // The template itself is untouched by applying it.
      final template = await templateRepository.findById('template-1');
      expect(template!.revision, 3);
    });

    test('an unknown template id throws', () async {
      final useCase = ApplySetupTemplate(
        authorizationPolicy: const AllowAllSetupPolicy(),
        templateRepository: InMemorySetupTemplateRepository(),
        snapshotRepository:
            InMemorySetupTemplateApplicationSnapshotRepository(),
        idGenerator: SequentialSetupTemplateApplicationSnapshotIdGenerator(),
      );

      expect(
        () => useCase(
          templateId: 'missing',
          organizationId: 'org-1',
          restaurantId: 'restaurant-1',
          branchId: 'branch-1',
          performedByStaffId: 'manager-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<UnknownSetupTemplateViolation>()),
      );
    });
  });
}
