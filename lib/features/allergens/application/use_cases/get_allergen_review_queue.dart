import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/ingredient_allergen_declaration_repository.dart';
import '../../domain/allergen_confidence.dart';
import '../../domain/allergen_declaration_status.dart';
import '../../domain/allergen_source_type.dart';
import '../../domain/ingredient_allergen_declaration.dart';

/// Lists every [IngredientAllergenDeclaration] a manager still needs
/// to act on — manager+ (`PosAuthorizedAction.manageAllergens`), Phase
/// 7 (`docs/decisions.md` ADR-024). "Allergen Review Queue for
/// unresolved/low-confidence" — a declaration qualifies when any of:
/// it's an unconfirmed AI suggestion, its status is
/// [AllergenDeclarationStatus.unknown], or its confidence is
/// [AllergenConfidence.low]/[AllergenConfidence.unknown]. Read-only;
/// never mutates anything.
class GetAllergenReviewQueue {
  const GetAllergenReviewQueue({
    required PosAuthorizationPolicy authorizationPolicy,
    required IngredientAllergenDeclarationRepository repository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final IngredientAllergenDeclarationRepository _repository;

  Future<List<IngredientAllergenDeclaration>> call({
    required String organizationId,
    required String performedByStaffId,
  }) async {
    const action = PosAuthorizedAction.manageAllergens;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final all = await _repository.findByOrganizationId(organizationId);
    return all
        .where((d) =>
            (d.sourceType == AllergenSourceType.aiSuggested &&
                !d.isConfirmedByHuman) ||
            d.status == AllergenDeclarationStatus.unknown ||
            d.confidence == AllergenConfidence.low ||
            d.confidence == AllergenConfidence.unknown)
        .toList(growable: false);
  }
}
