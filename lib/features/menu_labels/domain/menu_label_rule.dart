import '../../allergens/domain/allergen_type.dart';
import 'menu_label_type.dart';

/// One versioned rule defining when a [MenuLabelType] qualifies as a
/// suggestion — Phase 7 (`docs/decisions.md` ADR-024). Editing a rule
/// creates a new [MenuLabelRule] row (new `ruleVersion`) rather than
/// mutating an existing one — "label rule versions stored" — so a
/// past [MenuLabelSuggestion] always shows exactly which rule version
/// produced it.
///
/// [thresholdMilligramsOrKcal] is only meaningful for the three
/// nutrition-threshold label types (`highProtein`/`lowCalorie`/
/// `highFiber`); [freeFromAllergenType] is only meaningful for the two
/// free-from label types (`glutenFree`/`lactoseFree`). Every other
/// [MenuLabelType] has no automatic evaluator this phase — see that
/// enum's own doc comment.
class MenuLabelRule {
  const MenuLabelRule({
    required this.id,
    required this.organizationId,
    required this.labelType,
    required this.ruleVersion,
    required this.description,
    this.thresholdMilligramsOrKcal,
    this.freeFromAllergenType,
    required this.isActive,
    required this.createdAt,
    required this.createdByStaffId,
  });

  final String id;

  /// Tenant scoping — "no cross-tenant catalog mutation." A rule
  /// created for one organization is never evaluated against, or
  /// returned to, another.
  final String organizationId;
  final MenuLabelType labelType;
  final int ruleVersion;
  final String description;
  final int? thresholdMilligramsOrKcal;
  final AllergenType? freeFromAllergenType;
  final bool isActive;
  final DateTime createdAt;
  final String createdByStaffId;
}
