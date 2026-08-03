import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/setup_template_application_snapshot_id_generator.dart';
import '../../application/identity/setup_template_id_generator.dart';
import '../../data/setup_audit_entry_repository.dart';
import '../../data/setup_template_application_snapshot_repository.dart';
import '../../data/setup_template_repository.dart';
import '../../domain/setup_template.dart';
import '../../domain/setup_template_category.dart';
import '../../domain/setup_template_content.dart';

/// Central Riverpod wiring for `features/restaurant_setup` — Phase 7
/// (`docs/decisions.md` ADR-024). Seeded with one honest example public
/// template (Bowl & Salad, matching this platform's own real business)
/// — every field is a plain suggestion, never confidential recipe data.
final setupTemplateRepositoryProvider =
    Provider<SetupTemplateRepository>((ref) {
  return InMemorySetupTemplateRepository(seed: [
    SetupTemplate(
      id: 'setup-template-seed-1',
      category: SetupTemplateCategory.bowlAndSalad,
      name: 'Bowl & Salata Başlangıç Şablonu',
      categorySuggestions: const [
        TemplateCategorySuggestion(tempId: 't-cat-1', name: 'Bowl'),
        TemplateCategorySuggestion(tempId: 't-cat-2', name: 'Salata'),
        TemplateCategorySuggestion(tempId: 't-cat-3', name: 'İçecek'),
      ],
      ingredientReferences: const [
        TemplateIngredientReference(tempId: 't-ing-1', name: 'Tavuk Göğsü'),
        TemplateIngredientReference(tempId: 't-ing-2', name: 'Pirinç'),
        TemplateIngredientReference(tempId: 't-ing-3', name: 'Marul'),
      ],
      modifierPatterns: const [
        TemplateModifierPattern(
          tempId: 't-mod-1',
          name: 'Protein',
          optionNames: ['Tavuk', 'Somon', 'Falafel'],
        ),
      ],
      measurementUnitHints: const ['gram', 'porsiyon'],
      allergenHints: const ['gluten', 'susam'],
      isPublic: true,
      createdAt: DateTime(2026, 1, 1),
      revision: 1,
    ),
  ]);
});

final setupTemplateIdGeneratorProvider =
    Provider<SetupTemplateIdGenerator>((ref) {
  return SequentialSetupTemplateIdGenerator();
});

final setupTemplateApplicationSnapshotRepositoryProvider =
    Provider<SetupTemplateApplicationSnapshotRepository>((ref) {
  return InMemorySetupTemplateApplicationSnapshotRepository();
});

final setupTemplateApplicationSnapshotIdGeneratorProvider =
    Provider<SetupTemplateApplicationSnapshotIdGenerator>((ref) {
  return SequentialSetupTemplateApplicationSnapshotIdGenerator();
});

final setupAuditEntryRepositoryProvider =
    Provider<SetupAuditEntryRepository>((ref) {
  return InMemorySetupAuditEntryRepository();
});
