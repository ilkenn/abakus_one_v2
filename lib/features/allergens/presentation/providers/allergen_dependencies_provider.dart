import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/ingredient_allergen_declaration_id_generator.dart';
import '../../data/allergen_audit_entry_repository.dart';
import '../../data/ingredient_allergen_declaration_repository.dart';

/// Central Riverpod wiring for `features/allergens` — Phase 7
/// (`docs/decisions.md` ADR-024). Repository/id-generator providers
/// only, matching the pattern established across every other Phase 7
/// feature — no pre-wired, authorization-policy-baked use-case
/// providers.
final ingredientAllergenDeclarationRepositoryProvider =
    Provider<IngredientAllergenDeclarationRepository>((ref) {
  return InMemoryIngredientAllergenDeclarationRepository();
});

final ingredientAllergenDeclarationIdGeneratorProvider =
    Provider<IngredientAllergenDeclarationIdGenerator>((ref) {
  return SequentialIngredientAllergenDeclarationIdGenerator();
});

final allergenAuditEntryRepositoryProvider =
    Provider<AllergenAuditEntryRepository>((ref) {
  return InMemoryAllergenAuditEntryRepository();
});
