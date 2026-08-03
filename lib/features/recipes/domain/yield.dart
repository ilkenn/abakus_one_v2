import '../../inventory/domain/quantity.dart';

/// The total output a [RecipeVersion]/[SubRecipeVersion] produces from
/// its lines, and how many [PortionDefinition]-sized servings that
/// total divides into — Phase 7 (`docs/decisions.md` ADR-024).
class Yield {
  const Yield({required this.totalQuantity, required this.portionCount});

  final Quantity totalQuantity;

  /// How many portions [totalQuantity] divides into. Always a positive
  /// integer — a yield that produces nothing is not a valid recipe
  /// version.
  final int portionCount;
}
