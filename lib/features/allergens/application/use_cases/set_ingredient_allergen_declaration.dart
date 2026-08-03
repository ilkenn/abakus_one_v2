import '../../../../core/errors/business_rule_violation.dart';
import '../../../pos/domain/authorization/pos_authorization_policy.dart';
import '../../../pos/domain/authorization/pos_authorized_action.dart';
import '../../data/allergen_audit_entry_repository.dart';
import '../../data/ingredient_allergen_declaration_repository.dart';
import '../../domain/allergen_audit_entry.dart';
import '../../domain/allergen_audit_event_type.dart';
import '../../domain/allergen_confidence.dart';
import '../../domain/allergen_declaration_status.dart';
import '../../domain/allergen_source_type.dart';
import '../../domain/allergen_type.dart';
import '../../domain/ingredient_allergen_declaration.dart';
import '../identity/ingredient_allergen_declaration_id_generator.dart';

/// Creates or updates (upserts by ingredient+allergen pair) one
/// [IngredientAllergenDeclaration] — manager+
/// (`PosAuthorizedAction.manageAllergens`), Phase 7
/// (`docs/decisions.md` ADR-024). A [AllergenSourceType.manual] entry
/// requires a non-empty [reason] — "manual overrides require
/// reason+audit." A [AllergenSourceType.aiSuggested] entry is always
/// stored with `isConfirmedByHuman: false` regardless of any caller-
/// supplied value — "AI suggestions never authoritative" is enforced
/// structurally here, not left to caller discipline.
class SetIngredientAllergenDeclaration {
  const SetIngredientAllergenDeclaration({
    required PosAuthorizationPolicy authorizationPolicy,
    required IngredientAllergenDeclarationIdGenerator idGenerator,
    required IngredientAllergenDeclarationRepository repository,
    required AllergenAuditEntryRepository auditRepository,
  })  : _authorizationPolicy = authorizationPolicy,
        _idGenerator = idGenerator,
        _repository = repository,
        _auditRepository = auditRepository;

  final PosAuthorizationPolicy _authorizationPolicy;
  final IngredientAllergenDeclarationIdGenerator _idGenerator;
  final IngredientAllergenDeclarationRepository _repository;
  final AllergenAuditEntryRepository _auditRepository;

  Future<IngredientAllergenDeclaration> call({
    required String organizationId,
    required String ingredientId,
    required AllergenType allergenType,
    required AllergenDeclarationStatus status,
    required AllergenSourceType sourceType,
    AllergenConfidence? confidence,
    String? reason,
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

    final isManual = sourceType == AllergenSourceType.manual;
    if (isManual && (reason == null || reason.trim().isEmpty)) {
      throw const AllergenOverrideReasonRequiredViolation();
    }

    final existing = await _repository.findByIngredientAndAllergen(
        ingredientId, allergenType);
    final isAiSuggested = sourceType == AllergenSourceType.aiSuggested;
    final declaration = IngredientAllergenDeclaration(
      id: existing?.id ?? _idGenerator.nextIngredientAllergenDeclarationId(),
      organizationId: organizationId,
      ingredientId: ingredientId,
      allergenType: allergenType,
      status: status,
      sourceType: sourceType,
      confidence: confidence ??
          (isManual ? AllergenConfidence.high : AllergenConfidence.low),
      isConfirmedByHuman: !isAiSuggested,
      reviewedByStaffId: isAiSuggested ? null : existing?.reviewedByStaffId,
      reviewedAt: isAiSuggested ? null : existing?.reviewedAt,
      createdAt: existing?.createdAt ?? performedAt,
      revision: (existing?.revision ?? 0) + 1,
    );
    await _repository.save(declaration);

    await _auditRepository.appendEvent(AllergenAuditEntry(
      id: '${declaration.id}-audit-set-${performedAt.microsecondsSinceEpoch}',
      organizationId: organizationId,
      actorId: performedByStaffId,
      type: AllergenAuditEventType.declarationSet,
      description: isManual
          ? 'Allergen declaration for "$ingredientId" '
              '(${allergenType.name}) manually set to ${status.name}: $reason'
          : 'Allergen declaration for "$ingredientId" (${allergenType.name}) '
              'set to ${status.name} via ${sourceType.name}',
      targetEntityId: declaration.id,
      timestamp: performedAt,
    ));

    return declaration;
  }
}
