import 'package:abakus_one_v2/core/errors/business_rule_violation.dart';
import 'package:abakus_one_v2/features/admin/application/identity/localization_config_id_generator.dart';
import 'package:abakus_one_v2/features/admin/application/identity/translation_entry_id_generator.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/review_translation.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/set_fallback_language.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/set_language_enabled.dart';
import 'package:abakus_one_v2/features/admin/application/use_cases/set_translation_content.dart';
import 'package:abakus_one_v2/features/admin/data/admin_audit_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/data/localization_config_repository.dart';
import 'package:abakus_one_v2/features/admin/data/translation_entry_repository.dart';
import 'package:abakus_one_v2/features/admin/domain/localization/localization_scope_type.dart';
import 'package:abakus_one_v2/features/admin/domain/localization/supported_language.dart';
import 'package:abakus_one_v2/features/admin/domain/localization/translation_status.dart';
import 'package:flutter_test/flutter_test.dart';

import '../test_support/admin_test_fixtures.dart';

void main() {
  group('SetLanguageEnabled', () {
    test('enables a language, creating a default config on first touch',
        () async {
      final repository = InMemoryLocalizationConfigRepository();
      final useCase = SetLanguageEnabled(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialLocalizationConfigIdGenerator(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final config = await useCase(
        scopeType: LocalizationScopeType.branch,
        scopeId: 'branch-1',
        language: SupportedLanguage.en,
        enabled: true,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(config.enabledLanguages,
          {SupportedLanguage.tr, SupportedLanguage.en});
    });

    test('the master language (tr) can never be disabled', () async {
      final useCase = SetLanguageEnabled(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialLocalizationConfigIdGenerator(),
        repository: InMemoryLocalizationConfigRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          scopeType: LocalizationScopeType.branch,
          scopeId: 'branch-1',
          language: SupportedLanguage.tr,
          enabled: false,
          performedByStaffId: 'admin-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<MasterLanguageCannotBeDisabledViolation>()),
      );
    });

    test('cannot disable the current fallback language', () async {
      final repository = InMemoryLocalizationConfigRepository();
      final useCase = SetLanguageEnabled(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialLocalizationConfigIdGenerator(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );
      await useCase(
        scopeType: LocalizationScopeType.branch,
        scopeId: 'branch-1',
        language: SupportedLanguage.en,
        enabled: true,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );
      final setFallback = SetFallbackLanguage(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );
      await setFallback(
        scopeType: LocalizationScopeType.branch,
        scopeId: 'branch-1',
        language: SupportedLanguage.en,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(
        () => useCase(
          scopeType: LocalizationScopeType.branch,
          scopeId: 'branch-1',
          language: SupportedLanguage.en,
          enabled: false,
          performedByStaffId: 'admin-1',
          performedAt: DateTime(2026, 1, 3),
        ),
        throwsA(isA<FallbackLanguageCannotBeDisabledViolation>()),
      );
    });
  });

  group('SetFallbackLanguage', () {
    test('requires the target language to already be enabled', () async {
      final useCase = SetFallbackLanguage(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: InMemoryLocalizationConfigRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          scopeType: LocalizationScopeType.branch,
          scopeId: 'branch-1',
          language: SupportedLanguage.de,
          performedByStaffId: 'admin-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<FallbackLanguageMustBeEnabledViolation>()),
      );
    });
  });

  group('SetTranslationContent', () {
    test(
        'a machine-generated write cannot overwrite a manually edited '
        'entry', () async {
      final repository = InMemoryTranslationEntryRepository();
      final useCase = SetTranslationContent(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialTranslationEntryIdGenerator(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );
      await useCase(
        contentKey: 'menu.item.1.name',
        language: SupportedLanguage.en,
        content: 'Bowl Deluxe',
        isMachineGenerated: false,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(
        () => useCase(
          contentKey: 'menu.item.1.name',
          language: SupportedLanguage.en,
          content: 'Machine Bowl',
          isMachineGenerated: true,
          performedByStaffId: 'admin-1',
          performedAt: DateTime(2026, 1, 2),
        ),
        throwsA(isA<ManuallyEditedTranslationNotOverwritableViolation>()),
      );
    });

    test('a manual write always succeeds, even over a prior manual edit',
        () async {
      final repository = InMemoryTranslationEntryRepository();
      final useCase = SetTranslationContent(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialTranslationEntryIdGenerator(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );
      await useCase(
        contentKey: 'menu.item.1.name',
        language: SupportedLanguage.en,
        content: 'Bowl Deluxe',
        isMachineGenerated: false,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final updated = await useCase(
        contentKey: 'menu.item.1.name',
        language: SupportedLanguage.en,
        content: 'Bowl Supreme',
        isMachineGenerated: false,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(updated.content, 'Bowl Supreme');
      expect(updated.isManuallyEdited, isTrue);
      expect(updated.translationRevision, 2);
    });

    test('new content always starts in draft status', () async {
      final useCase = SetTranslationContent(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialTranslationEntryIdGenerator(),
        repository: InMemoryTranslationEntryRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      final entry = await useCase(
        contentKey: 'menu.item.1.name',
        language: SupportedLanguage.en,
        content: 'Bowl Deluxe',
        isMachineGenerated: false,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      expect(entry.status, TranslationStatus.draft);
    });
  });

  group('ReviewTranslation', () {
    test('moves a draft translation to approved', () async {
      final repository = InMemoryTranslationEntryRepository();
      final setContent = SetTranslationContent(
        authorizationPolicy: const AllowAllAdminPolicy(),
        idGenerator: SequentialTranslationEntryIdGenerator(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );
      final entry = await setContent(
        contentKey: 'menu.item.1.name',
        language: SupportedLanguage.en,
        content: 'Bowl Deluxe',
        isMachineGenerated: false,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 1),
      );

      final useCase = ReviewTranslation(
        authorizationPolicy: const AllowAllAdminPolicy(),
        repository: repository,
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );
      final reviewed = await useCase(
        translationEntryId: entry.id,
        newStatus: TranslationStatus.approved,
        performedByStaffId: 'admin-1',
        performedAt: DateTime(2026, 1, 2),
      );

      expect(reviewed.status, TranslationStatus.approved);
    });

    test('an unauthorized actor cannot review a translation', () async {
      final useCase = ReviewTranslation(
        authorizationPolicy: const DenyAllAdminPolicy(),
        repository: InMemoryTranslationEntryRepository(),
        auditRepository: InMemoryAdminAuditEntryRepository(),
      );

      expect(
        () => useCase(
          translationEntryId: 'translation-1',
          newStatus: TranslationStatus.approved,
          performedByStaffId: 'staff-1',
          performedAt: DateTime(2026, 1, 1),
        ),
        throwsA(isA<AuthorizationDeniedViolation>()),
      );
    });
  });
}
