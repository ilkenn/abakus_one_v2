import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/identity/recipe_id_generator.dart';
import '../../application/identity/recipe_ingredient_snapshot_id_generator.dart';
import '../../application/identity/recipe_modifier_impact_id_generator.dart';
import '../../application/identity/recipe_version_id_generator.dart';
import '../../application/identity/sub_recipe_id_generator.dart';
import '../../application/identity/sub_recipe_version_id_generator.dart';
import '../../data/recipe_audit_entry_repository.dart';
import '../../data/recipe_ingredient_snapshot_repository.dart';
import '../../data/recipe_modifier_impact_repository.dart';
import '../../data/recipe_repository.dart';
import '../../data/recipe_version_repository.dart';
import '../../data/sub_recipe_repository.dart';
import '../../data/sub_recipe_version_repository.dart';

/// Central Riverpod wiring for `features/recipes` — Phase 7
/// (`docs/decisions.md` ADR-024). Repository/id-generator providers
/// only, matching the pattern established in `features/inventory`'s
/// own dependencies provider — no pre-wired, authorization-policy-
/// baked use-case providers. Each id-generator provider is a single
/// cached `Provider` instance shared by every use case that needs it
/// (e.g. both `CreateRecipe` and `CreateRecipeVersion` read
/// [recipeVersionIdGeneratorProvider]) — using two separate generator
/// instances would let two different versions collide on the same
/// generated id, exactly the bug this sharing avoids.
final recipeRepositoryProvider = Provider<RecipeRepository>((ref) {
  return InMemoryRecipeRepository();
});

final recipeIdGeneratorProvider = Provider<RecipeIdGenerator>((ref) {
  return SequentialRecipeIdGenerator();
});

final recipeVersionRepositoryProvider =
    Provider<RecipeVersionRepository>((ref) {
  return InMemoryRecipeVersionRepository();
});

final recipeVersionIdGeneratorProvider =
    Provider<RecipeVersionIdGenerator>((ref) {
  return SequentialRecipeVersionIdGenerator();
});

final subRecipeRepositoryProvider = Provider<SubRecipeRepository>((ref) {
  return InMemorySubRecipeRepository();
});

final subRecipeIdGeneratorProvider = Provider<SubRecipeIdGenerator>((ref) {
  return SequentialSubRecipeIdGenerator();
});

final subRecipeVersionRepositoryProvider =
    Provider<SubRecipeVersionRepository>((ref) {
  return InMemorySubRecipeVersionRepository();
});

final subRecipeVersionIdGeneratorProvider =
    Provider<SubRecipeVersionIdGenerator>((ref) {
  return SequentialSubRecipeVersionIdGenerator();
});

final recipeIngredientSnapshotRepositoryProvider =
    Provider<RecipeIngredientSnapshotRepository>((ref) {
  return InMemoryRecipeIngredientSnapshotRepository();
});

final recipeIngredientSnapshotIdGeneratorProvider =
    Provider<RecipeIngredientSnapshotIdGenerator>((ref) {
  return SequentialRecipeIngredientSnapshotIdGenerator();
});

final recipeModifierImpactRepositoryProvider =
    Provider<RecipeModifierImpactRepository>((ref) {
  return InMemoryRecipeModifierImpactRepository();
});

final recipeModifierImpactIdGeneratorProvider =
    Provider<RecipeModifierImpactIdGenerator>((ref) {
  return SequentialRecipeModifierImpactIdGenerator();
});

final recipeAuditEntryRepositoryProvider =
    Provider<RecipeAuditEntryRepository>((ref) {
  return InMemoryRecipeAuditEntryRepository();
});
