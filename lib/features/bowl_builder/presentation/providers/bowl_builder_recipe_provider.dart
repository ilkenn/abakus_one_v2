import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../recipes/domain/recipe_line_flattener.dart';
import '../../../recipes/presentation/providers/recipe_dependencies_provider.dart';
import '../../application/identity/bowl_builder_ingredient_recipe_mapping_id_generator.dart';
import '../../application/identity/bowl_builder_recipe_snapshot_id_generator.dart';
import '../../application/use_cases/create_bowl_builder_recipe_snapshot.dart';
import '../../application/use_cases/resolve_dynamic_bowl_recipe.dart';
import '../../data/bowl_builder_ingredient_recipe_mapping_repository.dart';
import '../../data/bowl_builder_recipe_snapshot_repository.dart';

/// Riverpod wiring for the Phase 7H Bowl Builder recipe integration
/// (`docs/decisions.md` ADR-024) — additive to
/// `bowl_builder_provider.dart`, never replacing it. Repository/id-
/// generator providers plus [resolveDynamicBowlRecipeProvider] and
/// [createBowlBuilderRecipeSnapshotProvider] (both pure/unauthenticated,
/// so — unlike `manageRecipes`-gated use cases elsewhere — they are
/// safe to pre-wire as ready-to-call providers; see
/// `CreateBowlBuilderRecipeSnapshot`'s doc comment for why no
/// authorization policy is involved here).
final bowlBuilderIngredientRecipeMappingRepositoryProvider =
    Provider<BowlBuilderIngredientRecipeMappingRepository>((ref) {
  return InMemoryBowlBuilderIngredientRecipeMappingRepository();
});

final bowlBuilderIngredientRecipeMappingIdGeneratorProvider =
    Provider<BowlBuilderIngredientRecipeMappingIdGenerator>((ref) {
  return SequentialBowlBuilderIngredientRecipeMappingIdGenerator();
});

final bowlBuilderRecipeSnapshotRepositoryProvider =
    Provider<BowlBuilderRecipeSnapshotRepository>((ref) {
  return InMemoryBowlBuilderRecipeSnapshotRepository();
});

final bowlBuilderRecipeSnapshotIdGeneratorProvider =
    Provider<BowlBuilderRecipeSnapshotIdGenerator>((ref) {
  return SequentialBowlBuilderRecipeSnapshotIdGenerator();
});

final resolveDynamicBowlRecipeProvider =
    Provider<ResolveDynamicBowlRecipe>((ref) {
  return ResolveDynamicBowlRecipe(
    recipeRepository: ref.watch(recipeRepositoryProvider),
    recipeVersionRepository: ref.watch(recipeVersionRepositoryProvider),
    mappingRepository:
        ref.watch(bowlBuilderIngredientRecipeMappingRepositoryProvider),
    flattener: RecipeLineFlattener(
      subRecipeRepository: ref.watch(subRecipeRepositoryProvider),
      subRecipeVersionRepository: ref.watch(subRecipeVersionRepositoryProvider),
    ),
  );
});

final createBowlBuilderRecipeSnapshotProvider =
    Provider<CreateBowlBuilderRecipeSnapshot>((ref) {
  return CreateBowlBuilderRecipeSnapshot(
    idGenerator: ref.watch(bowlBuilderRecipeSnapshotIdGeneratorProvider),
    resolver: ref.watch(resolveDynamicBowlRecipeProvider),
    repository: ref.watch(bowlBuilderRecipeSnapshotRepositoryProvider),
  );
});
