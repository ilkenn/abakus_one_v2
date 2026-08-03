/// One menu-facing dish recipe's master record — Phase 7
/// (`docs/decisions.md` ADR-024). Organization-scoped, versioned
/// through [RecipeVersion] (see that class's doc comment for the
/// versioning contract). [isConfidential] restricts this recipe to
/// manager-tier+ access (`PosAuthorizedAction.manageRecipes`) — there
/// is no staff-tier or customer-facing read path for recipe
/// composition at all today, so confidentiality is currently enforced
/// by that access boundary already existing, not by a second check.
class Recipe {
  const Recipe({
    required this.id,
    required this.organizationId,
    required this.name,
    this.category,
    this.isConfidential = false,
    required this.currentVersionId,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String name;
  final String? category;
  final bool isConfidential;
  final String currentVersionId;
  final DateTime createdAt;
  final int revision;

  Recipe copyWith({
    String? name,
    String? category,
    bool clearCategory = false,
    bool? isConfidential,
    String? currentVersionId,
    required int revision,
  }) {
    return Recipe(
      id: id,
      organizationId: organizationId,
      name: name ?? this.name,
      category: clearCategory ? null : (category ?? this.category),
      isConfidential: isConfidential ?? this.isConfidential,
      currentVersionId: currentVersionId ?? this.currentVersionId,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
