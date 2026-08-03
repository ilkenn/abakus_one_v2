import 'allergen_confidence.dart';
import 'allergen_declaration_status.dart';
import 'allergen_source_type.dart';
import 'allergen_type.dart';

/// One ingredient's declared relationship to one [AllergenType] —
/// Phase 7 (`docs/decisions.md` ADR-024). One declaration per
/// (organization, ingredient, allergenType) triple, upserted (see
/// `SetIngredientAllergenDeclaration`).
///
/// [isConfirmedByHuman] is the structural enforcement of "AI
/// suggestions never authoritative": a [AllergenSourceType.aiSuggested]
/// declaration is created with this `false` and stays `false` until
/// `ConfirmIngredientAllergenDeclaration` runs — nothing in this
/// codebase reads an unconfirmed AI suggestion as if it were a real
/// classification (the Allergen Review Queue exists specifically to
/// surface these for a human to act on).
class IngredientAllergenDeclaration {
  const IngredientAllergenDeclaration({
    required this.id,
    required this.organizationId,
    required this.ingredientId,
    required this.allergenType,
    required this.status,
    required this.sourceType,
    required this.confidence,
    required this.isConfirmedByHuman,
    this.reviewedByStaffId,
    this.reviewedAt,
    required this.createdAt,
    required this.revision,
  });

  final String id;
  final String organizationId;
  final String ingredientId;
  final AllergenType allergenType;
  final AllergenDeclarationStatus status;
  final AllergenSourceType sourceType;
  final AllergenConfidence confidence;
  final bool isConfirmedByHuman;
  final String? reviewedByStaffId;
  final DateTime? reviewedAt;
  final DateTime createdAt;
  final int revision;

  IngredientAllergenDeclaration copyWith({
    AllergenDeclarationStatus? status,
    AllergenConfidence? confidence,
    bool? isConfirmedByHuman,
    String? reviewedByStaffId,
    DateTime? reviewedAt,
    required int revision,
  }) {
    return IngredientAllergenDeclaration(
      id: id,
      organizationId: organizationId,
      ingredientId: ingredientId,
      allergenType: allergenType,
      status: status ?? this.status,
      sourceType: sourceType,
      confidence: confidence ?? this.confidence,
      isConfirmedByHuman: isConfirmedByHuman ?? this.isConfirmedByHuman,
      reviewedByStaffId: reviewedByStaffId ?? this.reviewedByStaffId,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      createdAt: createdAt,
      revision: revision,
    );
  }
}
