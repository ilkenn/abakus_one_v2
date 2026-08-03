import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/allergen_audit_entry_repository.dart';
import '../../data/ingredient_allergen_declaration_repository.dart';
import '../../domain/allergen_audit_entry.dart';
import '../../domain/allergen_audit_event_type.dart';
import '../../domain/allergen_confidence.dart';
import '../../domain/allergen_declaration_status.dart';
import '../../domain/ingredient_allergen_declaration.dart';

/// A manager reviews and confirms (or corrects) an AI-suggested
/// [IngredientAllergenDeclaration] — manager+
/// (`PosAuthorizedAction.manageAllergens`), Phase 7
/// (`docs/decisions.md` ADR-024). The only way an AI-sourced
/// declaration's `isConfirmedByHuman` ever becomes `true`. The
/// reviewing manager may correct [status]/[confidence] in the same
/// call — a human confirming a suggestion is also free to fix it.
class ConfirmIngredientAllergenDeclaration {
  const ConfirmIngredientAllergenDeclaration({
    required PosAuthorizationPolicy authorizationPolicy,
    required IngredientAllergenDeclarationRepository repository,
    required AllergenAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final IngredientAllergenDeclarationRepository _repository;
  final AllergenAuditEntryRepository _auditRepository;

  Future<IngredientAllergenDeclaration> call({
    required String declarationId,
    AllergenDeclarationStatus? status,
    AllergenConfidence? confidence,
    required String performedByStaffId,
    required DateTime performedAt,
  }) async {
    const action = PosAuthorizedAction.manageAllergens;
    final authResult = await _authorizationPolicy.authorize(
      action: action,
      actorStaffId: performedByStaffId,
    );
    if (!authResult.granted) {
      throw AuthorizationDeniedViolation(actionName: action.name);
    }

    final declaration = await _repository.findById(declarationId);
    if (declaration == null) {
      throw UnknownAllergenEntityViolation(
        entityName: 'IngredientAllergenDeclaration',
        id: declarationId,
      );
    }

    final updated = declaration.copyWith(
      status: status,
      confidence: confidence,
      isConfirmedByHuman: true,
      reviewedByStaffId: performedByStaffId,
      reviewedAt: performedAt,
      revision: declaration.revision + 1,
    );
    await _repository.save(updated);

    await _auditRepository.appendEvent(AllergenAuditEntry(
      id: '${declaration.id}-audit-confirmed-'
          '${performedAt.microsecondsSinceEpoch}',
      organizationId: declaration.organizationId,
      actorId: performedByStaffId,
      type: AllergenAuditEventType.declarationConfirmed,
      description: 'Allergen declaration for "${declaration.ingredientId}" '
          '(${declaration.allergenType.name}) confirmed by human review',
      targetEntityId: declaration.id,
      timestamp: performedAt,
    ));

    return updated;
  }
}
