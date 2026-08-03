import '../../../recipes/domain/recipe_calculation_status.dart';
import '../../data/bowl_builder_recipe_snapshot_repository.dart';
import '../../domain/models/bowl_builder_recipe_snapshot.dart';
import '../identity/bowl_builder_recipe_snapshot_id_generator.dart';
import 'resolve_dynamic_bowl_recipe.dart';

/// Records an immutable, point-in-time [BowlBuilderRecipeSnapshot] for
/// one finalized Bowl Builder selection — Phase 7
/// (`docs/decisions.md` ADR-024). Called at cart finalization (the
/// closest analog "order submission" has in this app's actual
/// customer-facing flow today — Bowl Builder has never been connected
/// to the separate, real POS order-submission use case, and inventing
/// that connection is out of this phase's scope).
///
/// Deliberately **not** gated by [PosAuthorizationPolicy] — Bowl
/// Builder is customer-facing and this app's customer session
/// (`AuthSession`, phone+OTP) has no role/permission concept at all to
/// check against. This mirrors treating the call as system-triggered
/// by the customer's own already-authenticated action (finalizing
/// their own bowl into their own cart), the same way Phase 5E's
/// automatic visit-recording is triggered by an already-authorized
/// upstream action rather than re-checking a non-existent actor role.
///
/// [nutritionStatus]/[allergenStatus]/[costStatus] all start at
/// [RecipeCalculationStatus.notYetCalculated] — 7I/7J/7K/7M don't
/// exist yet this part.
class CreateBowlBuilderRecipeSnapshot {
  const CreateBowlBuilderRecipeSnapshot({
    required BowlBuilderRecipeSnapshotIdGenerator idGenerator,
    required ResolveDynamicBowlRecipe resolver,
    required BowlBuilderRecipeSnapshotRepository repository,
  })  : _idGenerator = idGenerator,
        _resolver = resolver,
        _repository = repository;

  final BowlBuilderRecipeSnapshotIdGenerator _idGenerator;
  final ResolveDynamicBowlRecipe _resolver;
  final BowlBuilderRecipeSnapshotRepository _repository;

  Future<BowlBuilderRecipeSnapshot> call({
    required String contextId,
    required String organizationId,
    String? branchId,
    String? baseRecipeId,
    required Map<String, int> selections,
    required int priceBasisMinorUnits,
    required String priceBasisCurrencyCode,
    required DateTime performedAt,
  }) async {
    final resolution = await _resolver(
      baseRecipeId: baseRecipeId,
      selections: selections,
    );

    final snapshot = BowlBuilderRecipeSnapshot(
      id: _idGenerator.nextBowlBuilderRecipeSnapshotId(),
      contextId: contextId,
      organizationId: organizationId,
      branchId: branchId,
      baseRecipeId: baseRecipeId,
      baseRecipeVersionId: resolution.baseRecipeVersionId,
      selections: [
        for (final entry in selections.entries)
          if (entry.value > 0)
            BowlBuilderSelectionLine(
              bowlBuilderIngredientId: entry.key,
              quantity: entry.value,
            ),
      ],
      resolvedIngredientLines: [
        for (final line in resolution.resolvedLines)
          BowlBuilderResolvedIngredientLine(
            ingredientId: line.ingredientId,
            quantity: line.quantity,
          ),
      ],
      nutritionStatus: RecipeCalculationStatus.notYetCalculated,
      allergenStatus: RecipeCalculationStatus.notYetCalculated,
      costStatus: RecipeCalculationStatus.notYetCalculated,
      priceBasisMinorUnits: priceBasisMinorUnits,
      priceBasisCurrencyCode: priceBasisCurrencyCode,
      createdAt: performedAt,
    );
    await _repository.save(snapshot);
    return snapshot;
  }
}
