import '../../inventory/domain/quantity.dart';

/// The size of a single serving portion a [RecipeVersion]/
/// [SubRecipeVersion] produces — Phase 7 (`docs/decisions.md`
/// ADR-024). Distinct from [Yield] — a portion is what one customer
/// receives; a yield is the total the recipe as a whole produces.
class PortionDefinition {
  const PortionDefinition({required this.quantity, this.description});

  final Quantity quantity;
  final String? description;
}
