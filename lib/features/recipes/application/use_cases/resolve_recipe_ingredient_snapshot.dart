import '../../../../core/errors/business_rule_violation.dart';
import '../../../inventory/data/ingredient_repository.dart';
import '../../../inventory/domain/quantity.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/recipe_audit_entry_repository.dart';
import '../../data/recipe_ingredient_snapshot_repository.dart';
import '../../data/recipe_repository.dart';
import '../../data/recipe_version_repository.dart';
import '../../data/sub_recipe_repository.dart';
import '../../data/sub_recipe_version_repository.dart';
import '../../domain/recipe_audit_entry.dart';
import '../../domain/recipe_audit_event_type.dart';
import '../../domain/recipe_ingredient_snapshot.dart';
import '../../domain/recipe_line.dart';
import '../identity/recipe_ingredient_snapshot_id_generator.dart';

class _ResolvedLine {
  const _ResolvedLine(this.ingredientId, this.quantity);
  final String ingredientId;
  final Quantity quantity;
}

/// Flattens a [RecipeVersion]'s lines — recursively expanding any
/// nested [SubRecipe] lines down to raw [Ingredient]s — and persists
/// the result as [RecipeIngredientSnapshot] rows tied to that one,
/// fixed `recipeVersionId` — Phase 7 (`docs/decisions.md` ADR-024).
/// manager+ (`PosAuthorizedAction.manageRecipes`) — resolving exposes
/// full recipe composition, which is confidentiality-gated the same
/// way creating one is.
///
/// Scaling through nested sub-recipes is carried as an exact
/// numerator/denominator pair through the recursion and only divided
/// once, at each ingredient leaf — avoids compounding floating-point
/// rounding error across nesting levels (a single integer truncation
/// per leaf, never a chain of `double` multiplications).
///
/// Detects (and rejects) a sub-recipe that transitively references
/// itself, rather than recursing forever.
class ResolveRecipeIngredientSnapshot {
  const ResolveRecipeIngredientSnapshot({
    required PosAuthorizationPolicy authorizationPolicy,
    required RecipeIngredientSnapshotIdGenerator idGenerator,
    required RecipeRepository recipeRepository,
    required RecipeVersionRepository recipeVersionRepository,
    required SubRecipeRepository subRecipeRepository,
    required SubRecipeVersionRepository subRecipeVersionRepository,
    required IngredientRepository ingredientRepository,
    required RecipeIngredientSnapshotRepository snapshotRepository,
    required RecipeAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _recipeRepository = recipeRepository,
        _recipeVersionRepository = recipeVersionRepository,
        _subRecipeRepository = subRecipeRepository,
        _subRecipeVersionRepository = subRecipeVersionRepository,
        _ingredientRepository = ingredientRepository,
        _snapshotRepository = snapshotRepository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final RecipeIngredientSnapshotIdGenerator _idGenerator;
  final RecipeRepository _recipeRepository;
  final RecipeVersionRepository _recipeVersionRepository;
  final SubRecipeRepository _subRecipeRepository;
  final SubRecipeVersionRepository _subRecipeVersionRepository;
  final IngredientRepository _ingredientRepository;
  final RecipeIngredientSnapshotRepository _snapshotRepository;
  final RecipeAuditEntryRepository _auditRepository;

  Future<List<RecipeIngredientSnapshot>> call({
    required String recipeId,
    String? recipeVersionId,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageRecipes;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final recipe = await _recipeRepository.findById(recipeId);
    if (recipe == null) {
      throw UnknownRecipeEntityViolation(entityName: 'Recipe', id: recipeId);
    }

    final versionId = recipeVersionId ?? recipe.currentVersionId;
    final version = await _recipeVersionRepository.findById(versionId);
    if (version == null) {
      throw UnknownRecipeEntityViolation(
        entityName: 'RecipeVersion',
        id: versionId,
      );
    }

    final resolved = <_ResolvedLine>[];
    await _expand(
      lines: version.lines,
      scaleNumerator: 1,
      scaleDenominator: 1,
      visitedSubRecipeIds: const {},
      out: resolved,
    );

    final snapshots = <RecipeIngredientSnapshot>[];
    for (final line in resolved) {
      final ingredient =
          await _ingredientRepository.findById(line.ingredientId);
      final snapshot = RecipeIngredientSnapshot(
        id: _idGenerator.nextRecipeIngredientSnapshotId(),
        recipeId: recipeId,
        recipeVersionId: version.id,
        ingredientId: line.ingredientId,
        ingredientName: ingredient?.name ?? line.ingredientId,
        quantity: line.quantity,
        createdAt: performedAt,
      );
      await _snapshotRepository.save(snapshot);
      snapshots.add(snapshot);
    }

    await _auditRepository.appendEvent(RecipeAuditEntry(
      id: '${version.id}-audit-snapshot-${performedAt.microsecondsSinceEpoch}',
      organizationId: recipe.organizationId,
      actorId: performedByStaffId,
      type: RecipeAuditEventType.ingredientSnapshotResolved,
      description: 'Ingredient snapshot resolved for recipe "${recipe.name}" '
          'v${version.versionNumber} (${snapshots.length} lines)',
      targetEntityId: recipeId,
      timestamp: performedAt,
    ));

    return snapshots;
  }

  Future<void> _expand({
    required List<RecipeLine> lines,
    required int scaleNumerator,
    required int scaleDenominator,
    required Set<String> visitedSubRecipeIds,
    required List<_ResolvedLine> out,
  }) async {
    for (final line in lines) {
      if (line.referencesIngredient) {
        final scaledSmallestUnits =
            (line.quantity.smallestUnits * scaleNumerator) ~/ scaleDenominator;
        out.add(_ResolvedLine(
          line.ingredientId!,
          Quantity(scaledSmallestUnits, line.quantity.unit),
        ));
        continue;
      }

      final subRecipeId = line.subRecipeId!;
      if (visitedSubRecipeIds.contains(subRecipeId)) {
        throw RecipeCycleDetectedViolation(subRecipeId: subRecipeId);
      }

      final subRecipe = await _subRecipeRepository.findById(subRecipeId);
      if (subRecipe == null) {
        throw UnknownRecipeEntityViolation(
          entityName: 'SubRecipe',
          id: subRecipeId,
        );
      }
      final subVersion = await _subRecipeVersionRepository
          .findById(subRecipe.currentVersionId);
      if (subVersion == null) {
        throw UnknownRecipeEntityViolation(
          entityName: 'SubRecipeVersion',
          id: subRecipe.currentVersionId,
        );
      }

      final requestedQuantity = line.quantity;
      final totalYield = subVersion.yieldAmount.totalQuantity;
      if (requestedQuantity.unit != totalYield.unit) {
        throw UnitMismatchViolation(
          expectedUnitCode: totalYield.unit.code,
          actualUnitCode: requestedQuantity.unit.code,
        );
      }

      await _expand(
        lines: subVersion.lines,
        scaleNumerator: scaleNumerator * requestedQuantity.smallestUnits,
        scaleDenominator: scaleDenominator * totalYield.smallestUnits,
        visitedSubRecipeIds: {...visitedSubRecipeIds, subRecipeId},
        out: out,
      );
    }
  }
}
