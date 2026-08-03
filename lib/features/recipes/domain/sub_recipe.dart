/// A reusable preparation (e.g. "domates sos", "haşlanmış pirinç") that
/// one or more [Recipe]/[SubRecipe]s reference by quantity through a
/// [RecipeLine] — Phase 7 (`docs/decisions.md` ADR-024). Versioned and
/// confidentiality-gated identically to [Recipe]; kept as a distinct
/// type (not a flag on `Recipe`) so a `RecipeLine.subRecipeId`
/// reference is type-narrowed to only ever point at something meant to
/// be nested, never a menu-facing dish recipe.
class SubRecipe {
  const SubRecipe({
    required this.id,
    required this.organizationId,
    required this.name,
    this.isConfidential = false,
    required this.currentVersionId,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String name;
  final bool isConfidential;
  final String currentVersionId;
  final DateTime createdAt;
  final int revision;

  SubRecipe copyWith({
    String? name,
    bool? isConfidential,
    String? currentVersionId,
    required int revision,
  }) {
    return SubRecipe(
      id: id,
      organizationId: organizationId,
      name: name ?? this.name,
      isConfidential: isConfidential ?? this.isConfidential,
      currentVersionId: currentVersionId ?? this.currentVersionId,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
